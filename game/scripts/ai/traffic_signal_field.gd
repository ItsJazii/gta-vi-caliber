class_name TrafficSignalField
extends Node3D
## Batched ambient-traffic signal layer for the playable map (issue #61, LC4).
##
## Reads the district manifest, builds a RoadNetwork per chosen district from the
## same OSM road data the DistrictLoader uses, finds intersections on an even grid
## and drops a real mast-arm signal at each: a kerb pole, an arm over the
## carriageway, and four heads (one per approach) of stacked red/amber/green
## lenses. ALL of that geometry is drawn through a handful of MultiMeshes — the
## poles, arms, housings and backboards are static, and every lens in the city
## shares one MultiMesh whose per-instance colour (driven by shaders/traffic_lens)
## is repainted only when a junction's phase flips. So the whole signalled city
## costs a few draw calls regardless of how many junctions there are.
##
## The node's junction list keeps each TrafficSignal clock centred on its stop
## line; TrafficDirector calls `must_hold()` to gate approaching cars. Pure phase
## and geometry maths stay in TrafficSignal / TrafficJunctions.

const ARM_Y := 5.4
const HEAD_DROP := 0.3
const POLE_H := ARM_Y + 0.3
# Four heads around the cluster: local XZ offset, facing yaw, and which axis.
const HEADS := [
	{"off": Vector2(0.33, 0.0), "yaw": -PI * 0.5, "axis": TrafficSignal.Axis.EW},
	{"off": Vector2(-0.33, 0.0), "yaw": PI * 0.5, "axis": TrafficSignal.Axis.EW},
	{"off": Vector2(0.0, 0.33), "yaw": PI, "axis": TrafficSignal.Axis.NS},
	{"off": Vector2(0.0, -0.33), "yaw": 0.0, "axis": TrafficSignal.Axis.NS},
]
# The three lens slots top-to-bottom and which light each shows.
const LENS_Y := [0.6, 0.0, -0.6]
const LENS_LIGHT := [TrafficSignal.Light.RED, TrafficSignal.Light.YELLOW, TrafficSignal.Light.GREEN]
const COLORS := {
	TrafficSignal.Light.GREEN: Color(0.1, 0.9, 0.25),
	TrafficSignal.Light.YELLOW: Color(1.0, 0.72, 0.1),
	TrafficSignal.Light.RED: Color(0.95, 0.12, 0.12),
}

@export_file("*.json") var manifest_path: String = "res://assets/world/districts.json"
## Cap on signalled junctions per district. High by default so EVERY 4-way
## crossroads (see TrafficJunctions.JUNCTION_DEGREE) gets a real light; T-junctions
## and bends are skipped, so the count stays sensible without a tight cap.
@export var per_district: int = 100000
## Grid cell (m): at most one signal per cell. Tiny so each separate crossroads
## gets its own light instead of being thinned for even spacing.
@export var min_spacing: float = 1.0
## Metres from the junction centre to the kerb corner the mast stands on.
@export var curb_offset: float = 6.0
## Phase-clock interval lengths (s) for each light's green and yellow. Kept short
## so a queue clears before the TrafficDirector's stuck-timeout would cull it.
@export var green_time: float = 6.0
@export var yellow_time: float = 2.0
## Only signal these districts (the dense urban cores); empty = every district.
@export var districts: PackedStringArray = ["downtown_miami", "brickell"]

var _rng := RandomNumberGenerator.new()
# Per junction: {clock: TrafficSignal, center: Vector3, lens_base: int, last: int}.
var _junctions: Array = []
var _lens_mm: MultiMesh
var _thread: Thread = null
var _poll_after := 1


func _ready() -> void:
	add_to_group("traffic_signal_field")
	_rng.randomize()
	# Parse the district road graphs off the main thread: that work is heavy and
	# would otherwise compete with district streaming during the load window,
	# starving spawn-time systems (e.g. the wanted tracker). The cheap MultiMesh
	# assembly runs on the main thread once the frames are ready, a beat after
	# load. RoadNetwork/GeoProjection maths are pure RefCounted, safe off-thread.
	_thread = Thread.new()
	_thread.start(_collect_frames)


func _process(delta: float) -> void:
	if _thread != null:
		# One frame of grace so the worker is scheduled, then build as soon as it
		# is no longer running (wait_to_finish returns instantly once done).
		if _poll_after > 0:
			_poll_after -= 1
		elif not _thread.is_alive():
			var frames: Array = _thread.wait_to_finish()
			_thread = null
			if not frames.is_empty():
				_build(frames)
		return
	for j in _junctions:
		var clock: TrafficSignal = j["clock"]
		clock.tick(delta)
		if clock.phase() != j["last"]:
			j["last"] = clock.phase()
			_paint_junction(j)


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
		_thread = null


## How many signalled junctions exist.
func junction_count() -> int:
	return _junctions.size()


## World centre (stop-line origin) of junction `i`.
func junction_center(i: int) -> Vector3:
	return _junctions[i]["center"]


## Reset every junction to NS-green / EW-red — deterministic state for probes.
func reset_all() -> void:
	for j in _junctions:
		(j["clock"] as TrafficSignal).reset()
		j["last"] = -1
		_paint_junction(j)


## True if a signalled junction ahead shows red/yellow for this car's approach.
## Scans all junctions; only one can be within a car's stop band at a time.
func must_hold(car_pos: Vector3, car_heading: Vector3, car_speed: float) -> bool:
	var axis := TrafficJunctions.axis_for(car_heading)
	for j in _junctions:
		var clock: TrafficSignal = j["clock"]
		var light := clock.light_for(axis)
		if TrafficJunctions.should_hold(
			j["center"], car_pos, car_heading, car_speed, light, 16.0, 6.0, 6.0
		):
			return true
	return false


# --- build -------------------------------------------------------------------


## Gather {center, corner_offset} for every signalled junction across districts.
func _collect_frames() -> Array:
	var frames: Array = []
	var manifest := _load(manifest_path)
	for d in manifest.get("districts", []):
		if not districts.is_empty() and not districts.has(String(d.get("name", ""))):
			continue
		var data := _load(String(d.get("data", "")))
		if data.is_empty() or not data.has("origin"):
			continue
		var origin: Dictionary = data["origin"]
		var proj := GeoProjection.new(origin["lat"], origin["lon"])
		var net := RoadNetwork.from_district(
			data.get("roads", []), proj, 2.0, RoadNetwork.DRIVEABLE
		)
		if net.segment_count() == 0:
			continue
		for hit in TrafficJunctions.find_signalled(net, per_district, min_spacing):
			frames.append(TrafficJunctions.junction_frame(net, hit["node"], curb_offset))
	return frames


func _build(frames: Array) -> void:
	var n := frames.size()
	var pole_mm := _add_mm(_cyl(0.14, POLE_H), n, _dark_metal(), false)
	var arm_mm := _add_mm(_box(Vector3(1.0, 0.14, 0.14)), n, _dark_metal(), false)
	var housing_mm := _add_mm(_box(Vector3(0.6, 1.9, 0.3)), n * 4, _housing_mat(), false)
	var board_mm := _add_mm(_box(Vector3(1.0, 2.3, 0.04)), n * 4, _board_mat(), false)
	var lens_mat := ShaderMaterial.new()
	lens_mat.shader = load("res://shaders/traffic_lens.gdshader")
	_lens_mm = _add_mm(_sphere(0.26), n * 12, lens_mat, true).multimesh

	for i in n:
		var center: Vector3 = frames[i]["center"]
		var corner: Vector3 = frames[i]["corner_offset"]
		pole_mm.multimesh.set_instance_transform(i, _pole_xform(center, corner))
		arm_mm.multimesh.set_instance_transform(i, _arm_xform(center, corner))
		for h in 4:
			var head := _head_xform(center, h)
			housing_mm.multimesh.set_instance_transform(i * 4 + h, head)
			board_mm.multimesh.set_instance_transform(
				i * 4 + h, head * Transform3D(Basis(), Vector3(0.0, 0.0, 0.16))
			)
			for s in 3:
				var li := (i * 4 + h) * 3 + s
				_lens_mm.set_instance_transform(
					li, head * Transform3D(Basis(), Vector3(0.0, LENS_Y[s], -0.18))
				)
		var clock := TrafficSignal.new(green_time, yellow_time)
		clock.tick(_rng.randf() * (2.0 * green_time + 2.0 * yellow_time))  # desync
		var rec := {"clock": clock, "center": center, "lens_base": i * 12, "last": -1}
		_junctions.append(rec)
		_paint_junction(rec)


## Repaint a junction's 12 lens instances for its current phase.
func _paint_junction(j: Dictionary) -> void:
	var clock: TrafficSignal = j["clock"]
	var base: int = j["lens_base"]
	for h in 4:
		var axis: int = HEADS[h]["axis"]
		var active := clock.light_for(axis)
		for s in 3:
			var lens_light: int = LENS_LIGHT[s]
			var col: Color = COLORS[lens_light]
			var lit := lens_light == active
			var c := (
				Color(col.r, col.g, col.b, 1.0)
				if lit
				else Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 0.0)
			)
			_lens_mm.set_instance_color(base + h * 3 + s, c)


# --- per-instance transforms -------------------------------------------------


func _pole_xform(center: Vector3, corner: Vector3) -> Transform3D:
	return Transform3D(Basis(), center + Vector3(corner.x, POLE_H * 0.5, corner.z))


func _arm_xform(center: Vector3, corner: Vector3) -> Transform3D:
	var length := maxf(corner.length(), 0.01)
	var dir := corner / length
	var basis := (
		Basis(Vector3.UP, atan2(-dir.z, dir.x)) * Basis.from_scale(Vector3(length, 1.0, 1.0))
	)
	return Transform3D(basis, center + Vector3(corner.x * 0.5, ARM_Y, corner.z * 0.5))


func _head_xform(center: Vector3, h: int) -> Transform3D:
	var off: Vector2 = HEADS[h]["off"]
	var origin := center + Vector3(off.x, ARM_Y - HEAD_DROP, off.y)
	return Transform3D(Basis(Vector3.UP, HEADS[h]["yaw"]), origin)


# --- mesh/material helpers ---------------------------------------------------


func _add_mm(mesh: Mesh, count: int, mat: Material, colored: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colored
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if mat != null:
		mmi.material_override = mat
	add_child(mmi)
	return mmi


func _cyl(radius: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius * 1.15
	m.height = height
	m.radial_segments = 10
	return m


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _sphere(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 12
	m.rings = 6
	return m


func _dark_metal() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.09, 0.09, 0.11)
	m.metallic = 0.6
	m.roughness = 0.5
	return m


func _housing_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.05, 0.06)
	m.roughness = 0.7
	return m


func _board_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.8, 0.15)
	m.roughness = 0.85
	return m


func _load(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
