extends SceneTree
## Asset integration gauntlet (docs/ASSET_PIPELINE.md §12): runs one asset
## through the standard battery — time-of-day sweep (noon / grazing golden hour
## / night / deep night), distance sweep (close / 50 m / 200 m+), a free-look
## motion arc with same-pose consecutive-frame flicker comparison, and a glass
## angle sweep when reflective/transparent materials are detected — all inside
## tests/asset_gauntlet.tscn, which replicates the live PR #33 sky + grade.
## Run with a renderer, not --headless:
##   ASSET=res://assets/buildings/poc_bayfront_tower.glb \
##   SHOT_DIR=session_captures/gauntlet/poc_bayfront_tower \
##   godot --path game --script res://tests/asset_gauntlet_capture.gd
## Exit code 0 only if every automated check passes; the contact sheet still
## needs human eyes (the gauntlet's automated checks are necessary, not
## sufficient).

const GAUNTLET_SCENE := "res://tests/asset_gauntlet.tscn"
const DEFAULT_ASSET := "res://assets/buildings/poc_bayfront_tower.glb"
const GROUND_SET := "res://assets/materials/asphalt_street_01"
const SETTLE_TIME := 40
const SETTLE_POSE := 12
const FOV := 65.0
const EYE := 1.7
const THUMB := Vector2i(384, 240)
const SHEET_COLS := 4

var _steps: Array[Dictionary] = []
var _step := 0
var _wait := 2
var _pair_name := ""
var _pair_lumas := PackedFloat32Array()
var _pair_image: Image
var _failures := PackedStringArray()
var _sheet_images: Array[Image] = []
var _controller: SkyController
var _camera: Camera3D
var _shot_dir := ""
var _built := false
## CHAR=1 wraps the asset in the real player rig (UAL retarget + state
## machine) and adds an animation-sanity lens: mid-walk frames, judged for
## mesh tearing by eye.
var _rig: Node3D = null
var _walking := false


func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	var stage := (load(GAUNTLET_SCENE) as PackedScene).instantiate()
	root.add_child(stage)

	var asset_path := OS.get_environment("ASSET")
	if asset_path == "":
		asset_path = DEFAULT_ASSET
	_shot_dir = OS.get_environment("SHOT_DIR")
	if _shot_dir == "":
		_shot_dir = "/tmp/gauntlet/%s" % asset_path.get_file().get_basename()

	var asset_scene := load(asset_path) as PackedScene
	if asset_scene == null:
		push_error("gauntlet: cannot load asset %s" % asset_path)
		quit(1)
		return
	if OS.get_environment("CHAR") == "1":
		_rig = (load("res://scenes/player/character_rig.tscn") as PackedScene).instantiate()
		_rig.set("visual_scene", asset_scene)
		stage.get_node("AssetAnchor").add_child(_rig)
	else:
		stage.get_node("AssetAnchor").add_child(asset_scene.instantiate())

	if stage.get_node_or_null("ReflectionProbe") == null:
		push_error("gauntlet: stage is missing its ReflectionProbe")
		quit(1)
		return

	var ground := stage.get_node("Ground") as MeshInstance3D
	ground.material_override = PbrMaterial.from_set(GROUND_SET, true, 1.0 / 6.0)

	_controller = stage.get_node("SkyController") as SkyController
	_camera = Camera3D.new()
	_camera.fov = FOV
	_camera.far = 2000.0
	stage.add_child(_camera)
	_camera.make_current()


func _process(_delta: float) -> bool:
	if not _built:
		_build_steps()
		_built = true
	if _rig != null:
		var speed: float = _rig.get("walk_speed") if _walking else 0.0
		_rig.call("animate", Vector3(0.0, 0.0, speed), true, 0.0, false, _delta)
	if _pair_name != "":
		_finish_pair()
		return false
	_wait -= 1
	if _wait > 0:
		return false
	if _step >= _steps.size():
		_finish_run()
		return true
	var s := _steps[_step]
	_step += 1
	match s.kind:
		"time":
			_controller.set_time_of_day(s.hour)
			_wait = SETTLE_TIME
		"move":
			_camera.look_at_from_position(s.pos, s.look, Vector3.UP)
			_wait = SETTLE_POSE
		"shoot":
			_capture(s.name)
			_wait = 1
		"shoot_pair":
			# frame A now; _finish_pair grabs frame B on the next process tick
			_pair_name = s.name
			_pair_image = root.get_texture().get_image()
			_pair_lumas = _sample_lumas(_pair_image)
			_wait = 1
		"walk":
			_walking = s.on
			_wait = SETTLE_POSE
	return false


## Build the whole battery once the asset is in the tree (AABB needs that).
func _build_steps() -> void:
	var aabb := _asset_aabb()
	var center := aabb.get_center()
	var radius_xz := maxf(aabb.size.x, aabb.size.z) * 0.5
	var radius := aabb.size.length() * 0.5
	var dir := Vector3(0.64, 0.0, 0.77)
	var gaze := Vector3(center.x, center.y * 0.9, center.z)

	var street := center + dir * (radius_xz + 25.0)
	street.y = EYE
	var close_d := GauntletChecks.framing_distance(radius * 0.35, FOV, 0.8)
	var shots_dist: Array[Vector2] = [
		Vector2(radius_xz + close_d, 0.4),  # close-up: frame a chunk, look mid-low
		Vector2(radius_xz + 50.0, 0.6),  # mid
		Vector2(radius_xz + 220.0, 0.9),  # far
	]
	if _rig != null:
		# skinned-mesh AABBs are animation-padded; use known human metrics
		center = Vector3(0.0, 0.95, 0.0)
		radius_xz = 0.5
		radius = 1.0
		# human-scale ranges: conversation, across-the-street, down-the-block
		street = center + dir * (radius_xz + 3.0)
		street.y = EYE
		gaze = Vector3(center.x, center.y, center.z)
		shots_dist = [
			Vector2(radius_xz + 1.8, 1.0),
			Vector2(radius_xz + 8.0, 1.0),
			Vector2(radius_xz + 30.0, 1.0),
		]

	# --- noon: time anchor, distance sweep, glass sweep ---
	_steps.append({"kind": "time", "hour": 12.0})
	_add_shot("01_time_noon", street, gaze)
	var dist_names := ["02_dist_close_noon", "03_dist_mid_noon", "04_dist_far_noon"]
	for i in shots_dist.size():
		var pos := center + dir * shots_dist[i].x
		pos.y = EYE
		var look := Vector3(center.x, center.y * shots_dist[i].y, center.z)
		_add_shot(dist_names[i], pos, look)
	if _has_glassy_materials():
		var face := Vector3(center.x, minf(center.y * 0.5, 10.0), aabb.end.z)
		var sweep := GauntletChecks.glass_sweep_poses(
			face, Vector3(0, 0, 1), 16.0, EYE, PackedFloat32Array([5.0, 30.0, 55.0, 75.0, 85.0])
		)
		for i in sweep.size():
			_add_shot(
				"05_glass_a%02d" % [int([5.0, 30.0, 55.0, 75.0, 85.0][i])],
				sweep[i].pos,
				sweep[i].look
			)

	# --- animation sanity (characters only): idle + two mid-walk frames ---
	if _rig != null:
		var anim_pos := center + dir * (radius_xz + 2.2)
		anim_pos.y = EYE
		var anim_look := Vector3(center.x, center.y, center.z)
		_add_shot("05_anim_idle", anim_pos, anim_look)
		_steps.append({"kind": "walk", "on": true})
		_add_shot("05_anim_walk_a", anim_pos, anim_look)
		_add_shot("05_anim_walk_b", anim_pos, anim_look)
		_steps.append({"kind": "walk", "on": false})

	# --- golden hour (grazing sun, known worst case): hero shot + motion arc ---
	_steps.append({"kind": "time", "hour": 17.8})
	_add_shot("06_time_golden", street, gaze)
	var arc_start := center + dir * (radius_xz + (12.0 if _rig != null else 55.0))
	var arc_end := center + dir * (radius_xz + (2.5 if _rig != null else 10.0))
	arc_start.y = EYE
	arc_end.y = EYE
	var arc := GauntletChecks.arc_poses(8, arc_start, arc_end, gaze, 35.0)
	for i in arc.size():
		_steps.append({"kind": "move", "pos": arc[i].pos, "look": arc[i].look})
		_steps.append({"kind": "shoot_pair", "name": "07_motion_p%d" % (i + 1)})

	# --- night: time anchor + the emissive-at-range cases ---
	_steps.append({"kind": "time", "hour": 22.0})
	_add_shot("08_time_night", street, gaze)
	for i in [1, 2]:
		var pos := center + dir * shots_dist[i].x
		pos.y = EYE
		var look := Vector3(center.x, center.y * shots_dist[i].y, center.z)
		_add_shot("09_dist_%s_night" % ["mid", "far"][i - 1], pos, look)

	# --- deep night ---
	_steps.append({"kind": "time", "hour": 2.0})
	_add_shot("10_time_deepnight", street, gaze)


func _add_shot(name: String, pos: Vector3, look: Vector3) -> void:
	_steps.append({"kind": "move", "pos": pos, "look": look})
	_steps.append({"kind": "shoot", "name": name})


func _asset_aabb() -> AABB:
	var anchor := root.find_child("AssetAnchor", true, false)
	var merged := AABB()
	var first := true
	for mesh in anchor.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		var box := mi.global_transform * mi.get_aabb()
		merged = box if first else merged.merge(box)
		first = false
	return merged


func _has_glassy_materials() -> bool:
	var anchor := root.find_child("AssetAnchor", true, false)
	if OS.get_environment("GLASS") == "1":
		return true
	if OS.get_environment("GLASS") == "0":
		return false
	for mesh in anchor.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null:
				continue
			if mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or mat.roughness <= 0.2:
				return true
	return false


func _capture(name: String) -> void:
	var image := root.get_texture().get_image()
	_check_pixels(name, _sample_lumas(image))
	_store(name, image)


## Second frame of a same-pose pair: compare against the first for flicker.
func _finish_pair() -> void:
	var image := root.get_texture().get_image()
	var lumas_b := _sample_lumas(image)
	var frac := GauntletChecks.flicker_fraction(_pair_lumas, lumas_b, GauntletChecks.FLICKER_DELTA)
	if frac > GauntletChecks.FLICKER_MAX_FRACTION:
		_failures.append("%s: flicker fraction %.4f (z-fighting/shimmer?)" % [_pair_name, frac])
	_check_pixels(_pair_name, _pair_lumas)
	_store(_pair_name, _pair_image)
	_pair_name = ""
	_pair_lumas = PackedFloat32Array()
	_pair_image = null
	_wait = 1


func _check_pixels(name: String, lumas: PackedFloat32Array) -> void:
	var stats := GauntletChecks.luma_stats(lumas)
	if GauntletChecks.is_blank(stats.mean):
		_failures.append("%s: blank capture (mean luma %.4f)" % [name, stats.mean])
	elif GauntletChecks.is_uniform(stats.stddev):
		_failures.append("%s: uniform capture (stddev %.4f)" % [name, stats.stddev])


func _store(name: String, image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	image.save_png("%s/%s.png" % [_shot_dir, name])
	print("gauntlet: saved %s.png" % name)
	var thumb := image.duplicate() as Image
	thumb.resize(THUMB.x, THUMB.y, Image.INTERPOLATE_LANCZOS)
	_sheet_images.append(thumb)


func _sample_lumas(image: Image) -> PackedFloat32Array:
	var lumas := PackedFloat32Array()
	for y in range(0, image.get_height(), 40):
		for x in range(0, image.get_width(), 40):
			lumas.append(image.get_pixel(x, y).get_luminance())
	return lumas


func _finish_run() -> void:
	_save_contact_sheet()
	if _failures.is_empty():
		print("gauntlet: ALL AUTOMATED CHECKS PASSED (%d shots)" % _sheet_images.size())
		print("gauntlet: contact sheet still needs human eyes before any verdict")
		quit(0)
		return
	for f in _failures:
		push_error("gauntlet FAIL — %s" % f)
	quit(1)


func _save_contact_sheet() -> void:
	if _sheet_images.is_empty():
		return
	var gap := 4
	var rows := ceili(float(_sheet_images.size()) / SHEET_COLS)
	var sheet := Image.create_empty(
		SHEET_COLS * (THUMB.x + gap) + gap, rows * (THUMB.y + gap) + gap, false, Image.FORMAT_RGB8
	)
	sheet.fill(Color(0.1, 0.1, 0.1))
	for i in _sheet_images.size():
		var x := gap + (i % SHEET_COLS) * (THUMB.x + gap)
		var y := gap + (i / SHEET_COLS) * (THUMB.y + gap)
		sheet.blit_rect(_sheet_images[i], Rect2i(Vector2i.ZERO, THUMB), Vector2i(x, y))
	sheet.save_png("%s/contact_sheet.png" % _shot_dir)
	print("gauntlet: saved contact_sheet.png")
