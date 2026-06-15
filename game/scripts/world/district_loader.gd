extends Node3D
## Builds a real-world city district from normalized OSM data. Reads footprints and road
## polylines, projects them into local metres via GeoProjection, and assembles
## batched meshes via CityBuilder. All heavy geometry math lives in those tested
## helpers; this node only orchestrates scene assembly.
##
## Buildings merge into one MeshInstance3D + one trimesh collider so the player
## and vehicles collide with the skyline; roads merge into a single flat,
## collision-free ribbon mesh laid just above the ground plane.

signal district_built(building_count: int, road_count: int)
signal streaming_step(duration_ms: float, kind: String)

enum DetailMode { HLOD, NEAR }
enum TileStage {
	BUILDINGS,
	ROADS,
	SIDEWALKS,
	OCCLUDER,
	COLLISION,
	GROUND,
	NAVIGATION,
	FACADES,
	ROOFTOPS,
	PALMS,
	PARKED,
	STREETLIGHTS,
	DOORS,
}

## Streetlight pole every ~this many metres of road, capped scene-wide and
## kept near the district origin (where the player spawns) so the cap is not
## eaten by far-away roads.
const STREETLIGHT_SPACING_M: float = 45.0
const MAX_STREETLIGHTS: int = 60
const STREETLIGHT_RADIUS_M: float = 250.0
const STREET_VISUAL_Y: float = 0.32
const SIDEWALK_VISUAL_Y: float = 0.28
const GROUND_SURFACE_Y: float = 0.4
const ROOFTOP_KEYS := [
	"rooftop_ac", "rooftop_tanks", "rooftop_houses", "rooftop_masts", "rooftop_beacons"
]
const ROOFTOP_NAMES := ["ACUnits", "WaterTanks", "Penthouses", "Masts", "Beacons"]

## res:// path to the district JSON (OSM-derived, ODbL).
@export_file("*.json") var district_path: String = "res://assets/world/downtown_miami.json"
## Build collision for buildings. Off speeds up pure-visual previews.
@export var build_collision: bool = true
## Spawn streetlight poles along roads (toggled at night by TimeOfDay).
@export var build_streetlights: bool = true
## Spawn "Enter" doors on enterable buildings (named or public-facing types).
@export var build_doors: bool = true
## Spawn a ground tile sized to this district's bounds (so a district drops into
## a multi-district world without a hand-placed plane under it).
@export var spawn_ground: bool = true
## Move the player + spawn marker onto this district's nearest street. In a
## multi-district scene only ONE loader should own the player (the streamer
## sets this false on the districts it pages in).
@export var place_player: bool = true
## Extra ground beyond the district footprint, in metres.
@export var ground_margin: float = 90.0
## Real-world streaming tile edge from docs/ARCHITECTURE.md.
@export var tile_size: float = 128.0
## Detailed render, collision, navigation, and props are limited to the near ring.
@export var near_radius: float = 900.0
## Hysteresis keeps near tiles from rebuilding at the detail boundary.
@export var near_unload_radius: float = 1100.0
## Re-evaluate near/HLOD ownership every few bounded streaming steps.
@export_range(1, 120) var detail_scan_steps: int = 20

var _building_mat: Material
var _facade_glass_mat: StandardMaterial3D
var _facade_lit_mat: StandardMaterial3D
var _roof_mat: StandardMaterial3D
var _road_mat: Material
var _sidewalk_mat: Material
var _parked_coupe_mesh: Mesh
var _parked_sedan_mesh: Mesh
var _palm_trunk_mesh: Mesh
var _palm_crown_mesh: Mesh
var _palm_bark_mat: StandardMaterial3D
var _palm_frond_mat: StandardMaterial3D
var _rooftop_meshes: Array[Mesh] = []
var _rooftop_materials: Array[Material] = []
var _build_thread: Thread
var _plan_mutex := Mutex.new()
var _thread_plan: Dictionary = {}
var _thread_finished: bool = false
var _plan: Dictionary = {}
var _projection: GeoProjection
var _chunk_data: Dictionary[Vector2i, Dictionary] = {}
var _chunk_nodes: Dictionary[Vector2i, Node3D] = {}
var _chunk_modes: Dictionary[Vector2i, int] = {}
var _pending_modes: Dictionary[Vector2i, int] = {}
var _active_coord: Vector2i
var _active_mode: int = -1
var _active_stage: int = -1
var _active_chunk: Node3D
var _active_data: Dictionary = {}
var _active_collision_commit: DistrictCollisionCommit
var _active_navigation_commit: DistrictNavigationCommit
var _active_rooftop_layer: int = 0
var _spawn_pending: bool = false
var _step_count: int = 0
var _initial_complete: bool = false
var _thread_started_usec: int = 0
var _background_build_ms: float = 0.0
var _max_step_ms: float = 0.0
var _tiles_built_total: int = 0


func _ready() -> void:
	# TimeOfDay fades our building-window glow through set_night_amount().
	add_to_group("night_emissive")
	if place_player:
		_set_starter_vehicles_frozen(true)
	_make_materials()
	_thread_started_usec = Time.get_ticks_usec()
	_build_thread = Thread.new()
	var error := _build_thread.start(_build_plan)
	if error != OK:
		push_error("district_loader: failed to start build thread for %s" % district_path)


func _exit_tree() -> void:
	if place_player:
		_set_starter_vehicles_frozen(false)
	if _build_thread != null:
		_build_thread.wait_to_finish()


func _build_plan() -> void:
	var prepared := DistrictTileBuilder.build_from_path(district_path, tile_size)
	_plan_mutex.lock()
	_thread_plan = prepared
	_thread_finished = true
	_plan_mutex.unlock()


## Consume at most one bounded main-thread operation. DistrictStreamer calls
## this once globally per physics frame across all resident districts.
func stream_one_step(observer: Vector3, velocity: Vector3) -> bool:
	if _plan.is_empty() and not _take_thread_plan(observer):
		return false
	if _spawn_pending:
		var spawn_start := Time.get_ticks_usec()
		_apply_spawn(_plan["spawn_position"], float(_plan["spawn_yaw"]))
		_spawn_pending = false
		_record_step(spawn_start, "spawn")
		return true
	if _active_chunk != null:
		var active_start := Time.get_ticks_usec()
		var kind := _stream_active_tile_step()
		_record_step(active_start, kind)
		return true

	_step_count += 1
	if _step_count % detail_scan_steps == 0:
		_refresh_detail_modes(observer)
	if _pending_modes.is_empty():
		_mark_initial_complete()
		return false

	var coords: Array[Vector2i] = []
	for coord: Vector2i in _pending_modes:
		coords.append(coord)
	var ordered := TileMath.load_order(coords, tile_size, observer, velocity)
	var coord := ordered[0]
	var mode: int = _pending_modes[coord]
	_pending_modes.erase(coord)

	var step_start := Time.get_ticks_usec()
	_start_chunk_replace(coord, mode)
	_record_step(step_start, "tile_root")
	return true


func streaming_stats() -> Dictionary:
	return {
		"prepared": not _plan.is_empty(),
		"tiles_total": _chunk_data.size(),
		"tiles_resident": _chunk_nodes.size(),
		"tiles_pending": _pending_modes.size() + (1 if _active_chunk != null else 0),
		"tiles_built_total": _tiles_built_total,
		"background_build_ms": _background_build_ms,
		"max_step_ms": _max_step_ms,
		"complete": _initial_complete,
	}


func _take_thread_plan(observer: Vector3) -> bool:
	_plan_mutex.lock()
	if not _thread_finished:
		_plan_mutex.unlock()
		return false
	_plan = _thread_plan
	_thread_plan = {}
	_plan_mutex.unlock()
	_build_thread.wait_to_finish()
	_build_thread = null
	_background_build_ms = float(Time.get_ticks_usec() - _thread_started_usec) / 1000.0
	if _plan.is_empty():
		push_error("district_loader: could not load %s" % district_path)
		return false

	var origin: Dictionary = _plan["origin"]
	_projection = GeoProjection.new(float(origin["lat"]), float(origin["lon"]))
	for chunk: Dictionary in _plan["chunks"]:
		var coord: Vector2i = chunk["coord"]
		_chunk_data[coord] = chunk
		_pending_modes[coord] = _desired_mode(coord, observer, -1)
	_spawn_pending = place_player
	return true


func _refresh_detail_modes(observer: Vector3) -> void:
	for coord: Vector2i in _chunk_nodes:
		var current: int = _chunk_modes[coord]
		var desired := _desired_mode(coord, observer, current)
		if desired != current:
			_pending_modes[coord] = desired


func _desired_mode(coord: Vector2i, observer: Vector3, current: int) -> int:
	var centre := TileMath.tile_center(coord, tile_size)
	var distance := Vector2(centre.x, centre.z).distance_to(Vector2(observer.x, observer.z))
	if current == DetailMode.NEAR:
		return DetailMode.NEAR if distance <= near_unload_radius else DetailMode.HLOD
	return DetailMode.NEAR if distance <= near_radius else DetailMode.HLOD


func _start_chunk_replace(coord: Vector2i, mode: int) -> void:
	if _chunk_nodes.has(coord):
		_chunk_nodes[coord].free()
		_chunk_nodes.erase(coord)
		_chunk_modes.erase(coord)
	_active_coord = coord
	_active_mode = mode
	_active_stage = TileStage.BUILDINGS
	_active_data = _chunk_data[coord]
	_active_chunk = Node3D.new()
	_active_chunk.name = "Tile_%d_%d" % [coord.x, coord.y]
	_active_chunk.add_to_group("district_tile")
	_active_chunk.set_meta("coord", coord)
	_active_chunk.set_meta("detail_mode", mode)
	add_child(_active_chunk)


func _stream_active_tile_step() -> String:
	var kind := "tile"
	var advance_stage := true
	match _active_stage:
		TileStage.BUILDINGS:
			var geo: Dictionary = (
				_active_data["buildings_geo"]
				if _active_mode == DetailMode.NEAR
				else _active_data["hlod_geo"]
			)
			_add_geo_mesh(_active_chunk, "Buildings", geo, _building_mat)
			kind = "tile_buildings"
		TileStage.ROADS:
			_add_geo_mesh(_active_chunk, "Roads", _active_data["roads_geo"], _road_mat)
			kind = "tile_roads"
		TileStage.SIDEWALKS:
			_add_geo_mesh(_active_chunk, "Sidewalks", _active_data["sidewalks_geo"], _sidewalk_mat)
			kind = "tile_sidewalks"
		TileStage.OCCLUDER:
			_add_occluder(_active_chunk, _active_data["hlod_geo"])
			kind = "tile_occluder"
		TileStage.COLLISION:
			if build_collision:
				if _active_collision_commit == null:
					_active_collision_commit = DistrictCollisionCommit.new(
						_active_data["buildings"] as Array, _projection
					)
				advance_stage = _active_collision_commit.step(_active_chunk)
				if advance_stage:
					_active_collision_commit = null
			kind = "tile_collision"
		TileStage.GROUND:
			if spawn_ground:
				_add_ground_chunk(_active_chunk, _active_coord)
			kind = "tile_ground"
		TileStage.NAVIGATION:
			if _active_navigation_commit == null:
				_active_navigation_commit = DistrictNavigationCommit.new(
					_active_data["navigation_vertices"], _active_data["navigation_polygons"]
				)
			advance_stage = _active_navigation_commit.step(_active_chunk)
			if advance_stage:
				_active_navigation_commit = null
			kind = "tile_navigation"
		TileStage.FACADES:
			DistrictFacadePanels.build_transforms(
				_active_chunk,
				_active_data["facade_dark"] as Array[Transform3D],
				_active_data["facade_lit"] as Array[Transform3D]
			)
			kind = "tile_facades"
		TileStage.ROOFTOPS:
			advance_stage = _stream_rooftop_layer()
			kind = "tile_rooftops"
		TileStage.PALMS:
			_build_palms(_active_data["roads"], _projection, _active_chunk, 18)
			kind = "tile_palms"
		TileStage.PARKED:
			_build_parked_cars(_active_data["roads"], _projection, _active_chunk, 4)
			kind = "tile_parked"
		TileStage.STREETLIGHTS:
			if build_streetlights:
				_build_streetlights(_active_data["roads"], _projection, _active_chunk, 1)
			kind = "tile_streetlights"
		TileStage.DOORS:
			if build_doors:
				BuildingDoors.build(_active_chunk, _active_data["buildings"], _projection, 2)
			kind = "tile_doors"

	if advance_stage:
		_active_stage += 1
	if (
		(_active_mode == DetailMode.HLOD and _active_stage > TileStage.OCCLUDER)
		or _active_stage > TileStage.DOORS
	):
		_finish_active_chunk()
	return kind


func _finish_active_chunk() -> void:
	_chunk_nodes[_active_coord] = _active_chunk
	_chunk_modes[_active_coord] = _active_mode
	_tiles_built_total += 1
	_active_mode = -1
	_active_stage = -1
	_active_chunk = null
	_active_data = {}
	_active_collision_commit = null
	_active_navigation_commit = null
	_active_rooftop_layer = 0
	_mark_initial_complete()


func _add_geo_mesh(parent: Node3D, node_name: String, geo: Dictionary, material: Material) -> void:
	var mesh := CityBuilder.arrays_to_mesh(geo)
	if mesh == null:
		return
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	parent.add_child(instance)


func _add_ground_chunk(parent: Node3D, coord: Vector2i) -> void:
	var centre := TileMath.tile_center(coord, tile_size)
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.position = Vector3(centre.x, 0.0, centre.z)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(tile_size, 1.0, tile_size)
	collision.shape = box
	collision.position = Vector3(0.0, GROUND_SURFACE_Y - box.size.y * 0.5, 0.0)
	body.add_child(collision)
	parent.add_child(body)


func _add_occluder(parent: Node3D, geo: Dictionary) -> void:
	var vertices: PackedVector3Array = geo.get("vertices", PackedVector3Array())
	var indices: PackedInt32Array = geo.get("indices", PackedInt32Array())
	if vertices.is_empty() or indices.is_empty():
		return
	var resource := ArrayOccluder3D.new()
	resource.set_arrays(vertices, indices)
	var instance := OccluderInstance3D.new()
	instance.name = "Occluder"
	instance.occluder = resource
	parent.add_child(instance)


func _record_step(start_usec: int, kind: String) -> void:
	var duration_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
	_max_step_ms = maxf(_max_step_ms, duration_ms)
	streaming_step.emit(duration_ms, kind)


func _mark_initial_complete() -> void:
	if (
		_initial_complete
		or _active_chunk != null
		or _chunk_nodes.size() != _chunk_data.size()
		or not _pending_modes.is_empty()
	):
		return
	_initial_complete = true
	var building_count := int(_plan["building_count"])
	var road_count := int(_plan["road_count"])
	print(
		(
			"district_loader: streamed %s — %d buildings, %d roads, %d tiles"
			% [_plan["name"], building_count, road_count, _chunk_nodes.size()]
		)
	)
	district_built.emit(building_count, road_count)


func _stream_rooftop_layer() -> bool:
	while _active_rooftop_layer < ROOFTOP_KEYS.size():
		var index := _active_rooftop_layer
		_active_rooftop_layer += 1
		var transforms: Array[Transform3D] = _active_data[ROOFTOP_KEYS[index]]
		if transforms.is_empty():
			continue
		var container := _active_chunk.get_node_or_null("Rooftops") as Node3D
		if container == null:
			container = Node3D.new()
			container.name = "Rooftops"
			_active_chunk.add_child(container)
		_rooftop_layer(
			ROOFTOP_NAMES[index],
			_rooftop_meshes[index],
			_rooftop_materials[index],
			transforms,
			container
		)
		return _active_rooftop_layer >= ROOFTOP_KEYS.size()
	return true


## Pack a set of instance transforms into one MultiMeshInstance3D (a single draw
## call) under `parent`. No-op for an empty layer.
func _rooftop_layer(
	layer_name: String, mesh: Mesh, mat: Material, transforms: Array[Transform3D], parent: Node3D
) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = layer_name
	mmi.multimesh = mm
	mmi.material_override = mat
	parent.add_child(mmi)


## Palm-lined avenues — the signature Miami streetscape. Trunks and frond crowns
## are two MultiMeshes sharing one per-instance transform list, so hundreds of
## palms cost two draw calls. The crown mesh is authored at the trunk top so the
## same transform places both. Denser + on more roads than the broadleaf trees.
func _build_palms(
	roads: Array, proj: GeoProjection, target_parent: Node3D = null, limit: int = 900
) -> void:
	if _palm_trunk_mesh == null or _palm_crown_mesh == null:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = 9151
	var transforms: Array[Transform3D] = []
	for r in roads:
		if transforms.size() >= limit:
			break
		var width := float(r.get("width_m", 0.0))
		if width < 7.0:
			continue
		var path := _project_ring(r["path"], proj)
		var kerb := width * 0.5 + 2.2
		# Wide avenues get palms on BOTH kerbs (a palm-lined boulevard); narrower
		# streets get a single row.
		var sides: Array[float] = [kerb]
		if width >= 9.0:
			sides.append(-kerb)
		for off in sides:
			for p in StreetLight.sample_along(path, 18.0, off):
				if transforms.size() >= limit:
					break
				var s := rng.randf_range(0.82, 1.3)
				var basis := Basis.from_euler(Vector3(0.0, rng.randf() * TAU, 0.0)).scaled(
					Vector3(s, s, s)
				)
				transforms.append(Transform3D(basis, Vector3(p.x, 0.0, p.y)))

	if transforms.is_empty():
		return
	var parent := target_parent if target_parent != null else self
	_add_palm_layer(_palm_trunk_mesh, _palm_bark_mat, transforms, "PalmTrunks", parent)
	_add_palm_layer(_palm_crown_mesh, _palm_frond_mat, transforms, "PalmCrowns", parent)


func _add_palm_layer(
	mesh: Mesh,
	mat: Material,
	transforms: Array[Transform3D],
	node_name: String,
	target_parent: Node3D = null
) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.visibility_range_end = 300.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	(target_parent if target_parent != null else self).add_child(mmi)


func _build_parked_cars(
	roads: Array, proj: GeoProjection, target_parent: Node3D, limit: int
) -> void:
	if _parked_coupe_mesh == null or _parked_sedan_mesh == null:
		return

	var coupe_transforms: Array[Transform3D] = []
	var sedan_transforms: Array[Transform3D] = []
	var placed := 0
	for road: Dictionary in roads:
		if placed >= limit:
			break
		var width := float(road.get("width_m", 0.0))
		if width < 7.0:
			continue
		var path := _project_ring(road.get("path", []), proj)
		var offset := width * 0.5 - 1.1
		for index in path.size() - 1:
			var start := path[index]
			var segment := path[index + 1] - start
			var segment_length := segment.length()
			if segment_length < 9.0:
				continue
			var direction := segment / segment_length
			var normal := Vector2(-direction.y, direction.x)
			var yaw := atan2(direction.x, direction.y)
			var distance := 5.0
			while distance < segment_length - 4.0 and placed < limit:
				var point := start + direction * distance + normal * offset
				var transform := Transform3D(
					Basis.from_euler(Vector3(0.0, yaw, 0.0)),
					Vector3(
						point.x,
						STREET_VISUAL_Y + VehicleVisualLibrary.MODEL_FLOOR_OFFSET_Y,
						point.y
					)
				)
				if placed % 2 == 0:
					coupe_transforms.append(transform)
				else:
					sedan_transforms.append(transform)
				placed += 1
				distance += 14.0
	_add_parked_car_layer(_parked_coupe_mesh, coupe_transforms, "ParkedSportCoupes", target_parent)
	_add_parked_car_layer(
		_parked_sedan_mesh, sedan_transforms, "ParkedClassicSedans", target_parent
	)


func _add_parked_car_layer(
	mesh: Mesh, transforms: Array[Transform3D], node_name: String, parent: Node3D
) -> void:
	if transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	parent.add_child(instance)


func _build_streetlights(
	roads: Array, proj: GeoProjection, target_parent: Node3D, limit: int
) -> void:
	var transforms: Array[Transform3D] = []
	for road: Dictionary in roads:
		if transforms.size() >= limit:
			break
		var width := float(road.get("width_m", 0.0))
		if width < 8.0:
			continue
		var path := _project_ring(road.get("path", []), proj)
		for point: Vector2 in StreetLight.sample_along(path, 42.0, width * 0.5 + 1.2):
			transforms.append(Transform3D(Basis.IDENTITY, Vector3(point.x, 0.0, point.y)))
			if transforms.size() >= limit:
				break
	if transforms.is_empty():
		return

	var root := Node3D.new()
	root.name = "StreetLights"
	target_parent.add_child(root)
	var pole_material := StandardMaterial3D.new()
	pole_material.albedo_color = Color(0.1, 0.1, 0.12)
	pole_material.metallic = 0.6
	pole_material.roughness = 0.5
	var lamp_material := StandardMaterial3D.new()
	lamp_material.albedo_color = Color(1.0, 0.92, 0.72)
	lamp_material.emission_enabled = true
	lamp_material.emission = Color(1.0, 0.85, 0.55)
	lamp_material.emission_energy_multiplier = 2.5
	var switch := StreetlightSwitch.new()
	switch.setup(lamp_material, lamp_material.emission_energy_multiplier)
	root.add_child(switch)

	var pole_mesh := BoxMesh.new()
	pole_mesh.size = Vector3(0.14, 5.0, 0.14)
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.5, 0.22, 0.32)
	var pole_transforms: Array[Transform3D] = []
	var head_transforms: Array[Transform3D] = []
	for transform: Transform3D in transforms:
		pole_transforms.append(
			Transform3D(transform.basis, transform.origin + Vector3(0.0, 2.65, 0.0))
		)
		head_transforms.append(
			Transform3D(transform.basis, transform.origin + Vector3(0.0, 5.15, 0.0))
		)
	_add_prop_layer("StreetlightPoles", pole_mesh, pole_material, pole_transforms, root, 200.0)
	_add_prop_layer("StreetlightHeads", head_mesh, lamp_material, head_transforms, root, 200.0)


func _add_prop_layer(
	node_name: String,
	mesh: Mesh,
	material: Material,
	transforms: Array[Transform3D],
	parent: Node3D,
	visibility_end: float
) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = material
	instance.visibility_range_end = visibility_end
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(instance)


func _project_ring(raw: Array, proj: GeoProjection) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for pair in raw:
		ring.append(proj.to_local_2d(pair[0], pair[1]))
	return ring


## TimeOfDay (group "night_emissive") fades building windows in/out, 0..1.
func set_night_amount(amount: float) -> void:
	var shaded := _building_mat as ShaderMaterial
	if shaded != null:
		shaded.set_shader_parameter("night_mix", amount)


func _apply_spawn(spawn: Vector3, yaw: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for marker in tree.get_nodes_in_group("spawn_points"):
		if marker is Node3D:
			(marker as Node3D).global_position = spawn
	for player in tree.get_nodes_in_group("player"):
		if player is Node3D:
			(player as Node3D).global_position = spawn + Vector3(0, 0.5, 0)
			var camera_rig := (player as Node).get_node_or_null("CameraRig") as Node3D
			if camera_rig != null:
				camera_rig.rotation.y = yaw
	_place_starter_vehicles(spawn, yaw)
	_build_spawn_vista(spawn, yaw)


func _place_starter_vehicles(spawn: Vector3, yaw: float) -> void:
	var vehicle_spawn := Vector3(spawn.x, STREET_VISUAL_Y + 0.6, spawn.z)
	var transforms := VehicleSpawnLayout.starter_transforms(vehicle_spawn, yaw)
	var vehicles := get_tree().get_nodes_in_group("starter_vehicles")
	for index in mini(vehicles.size(), transforms.size()):
		var vehicle := vehicles[index] as Node3D
		if vehicle == null:
			continue
		vehicle.global_transform = transforms[index]
		if vehicle is RigidBody3D:
			(vehicle as RigidBody3D).linear_velocity = Vector3.ZERO
			(vehicle as RigidBody3D).angular_velocity = Vector3.ZERO
			(vehicle as RigidBody3D).freeze = false


func _set_starter_vehicles_frozen(frozen: bool) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for vehicle: Node in tree.get_nodes_in_group("starter_vehicles"):
		if vehicle is RigidBody3D:
			(vehicle as RigidBody3D).freeze = frozen
			if frozen:
				_align_vehicle_visual_to_surface(vehicle as Node3D)


func _align_vehicle_visual_to_surface(vehicle: Node3D) -> void:
	var visual := VehicleVisualLibrary.first_mesh_instance(vehicle)
	if visual == null:
		return
	var bounds := visual.get_aabb()
	var bottom_y := INF
	for x: float in [bounds.position.x, bounds.end.x]:
		for y: float in [bounds.position.y, bounds.end.y]:
			for z: float in [bounds.position.z, bounds.end.z]:
				bottom_y = minf(bottom_y, (visual.global_transform * Vector3(x, y, z)).y)
	vehicle.global_position.y += STREET_VISUAL_Y - bottom_y


func _build_spawn_vista(spawn: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "SpawnVistaStreet"
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	root.position = Vector3(spawn.x, STREET_VISUAL_Y + 0.12, spawn.z) + forward * 4.0
	root.rotation.y = yaw
	add_child(root)

	var asphalt_mat := StandardMaterial3D.new()
	asphalt_mat.albedo_color = Color(0.025, 0.028, 0.03)
	asphalt_mat.roughness = 0.94
	asphalt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var road_mesh := BoxMesh.new()
	road_mesh.size = Vector3(18.0, 0.12, 160.0)
	_add_surface(root, "HeroRoad", road_mesh, asphalt_mat, Vector3.ZERO)

	var sidewalk_mat := StandardMaterial3D.new()
	sidewalk_mat.albedo_color = Color(0.30, 0.30, 0.28)
	sidewalk_mat.roughness = 0.88
	sidewalk_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var sidewalk_mesh := BoxMesh.new()
	sidewalk_mesh.size = Vector3(4.0, 0.12, 160.0)
	_add_surface(root, "LeftSidewalk", sidewalk_mesh, sidewalk_mat, Vector3(11.0, 0.04, 0.0))
	_add_surface(root, "RightSidewalk", sidewalk_mesh, sidewalk_mat, Vector3(-11.0, 0.04, 0.0))

	var paint_mat := StandardMaterial3D.new()
	paint_mat.albedo_color = Color(0.86, 0.82, 0.68)
	paint_mat.roughness = 0.82
	var dash_mesh := BoxMesh.new()
	dash_mesh.size = Vector3(0.22, 0.025, 4.8)
	for z in [-60.0, -48.0, -36.0, -24.0, -12.0, 0.0, 12.0, 24.0, 36.0, 48.0, 60.0]:
		_add_surface(root, "LaneDash", dash_mesh, paint_mat, Vector3(0.0, 0.07, z))

	var crosswalk_mesh := BoxMesh.new()
	crosswalk_mesh.size = Vector3(13.5, 0.025, 0.48)
	for z in [-70.0, -69.1, -68.2, 68.2, 69.1, 70.0]:
		_add_surface(root, "CrosswalkBar", crosswalk_mesh, paint_mat, Vector3(0.0, 0.075, z))

	_build_spawn_palms(root)
	_build_spawn_cones(root)


func _add_surface(parent: Node, node_name: String, mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _build_spawn_palms(parent: Node3D) -> void:
	var trunk_mesh := TreeMesh.to_mesh(TreeMesh.palm_trunk(8.0))
	var crown_mesh := TreeMesh.to_mesh(TreeMesh.palm_crown(11, 2.7, 8.0))
	if trunk_mesh == null or crown_mesh == null:
		return
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.52, 0.44, 0.34)
	bark.roughness = 0.92
	var frond := StandardMaterial3D.new()
	frond.albedo_color = Color(0.24, 0.45, 0.18)
	frond.roughness = 0.86
	frond.cull_mode = BaseMaterial3D.CULL_DISABLED

	for side in [-1.0, 1.0]:
		for i in 6:
			var z := -48.0 + float(i) * 19.0
			var palm := Node3D.new()
			palm.name = "SpawnPalm"
			palm.position = Vector3(side * 13.2, 0.0, z)
			palm.rotation.y = side * 0.25 + float(i) * 0.31
			var s := 0.86 + float(i % 3) * 0.08
			palm.scale = Vector3(s, s, s)
			parent.add_child(palm)
			_add_surface(palm, "Trunk", trunk_mesh, bark, Vector3.ZERO)
			_add_surface(palm, "Crown", crown_mesh, frond, Vector3.ZERO)


func _build_spawn_cones(parent: Node3D) -> void:
	var cone_mat := StandardMaterial3D.new()
	cone_mat.albedo_color = Color(1.0, 0.36, 0.08)
	cone_mat.roughness = 0.72
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.08
	cone_mesh.bottom_radius = 0.28
	cone_mesh.height = 0.72
	cone_mesh.radial_segments = 10
	for z in [-34.0, -18.0, 18.0, 34.0]:
		_add_surface(parent, "TrafficCone", cone_mesh, cone_mat, Vector3(7.4, 0.36, z))


func _make_materials() -> void:
	# Procedural facade/asphalt shaders — no texture assets. Fall back to plain
	# greybox materials so the district still builds if a shader goes missing.
	# (Consolidation per LOOP_HANDOFF: facade.gdshader won over the parallel
	# building.gdshader/building_windows.gdshader; TimeOfDay drives its
	# night_mix uniform through set_night_amount.)
	_building_mat = _shader_or_fallback("res://shaders/facade.gdshader", Color(0.62, 0.63, 0.66))
	_road_mat = _shader_or_fallback("res://shaders/road.gdshader", Color(0.33, 0.32, 0.31))
	_sidewalk_mat = _shader_or_fallback("res://shaders/sidewalk.gdshader", Color(0.62, 0.60, 0.56))
	# Photoreal asphalt grain from the Codex-generated tileable albedo.
	_set_detail_texture(_road_mat, "res://assets/textures/asphalt_albedo.png")
	# #160 facade PBR: bind the texture set onto the consolidated facade shader.
	FacadeMaterialBindings.apply_to(_building_mat)

	_facade_glass_mat = StandardMaterial3D.new()
	_facade_glass_mat.albedo_color = Color(0.045, 0.065, 0.085, 0.92)
	_facade_glass_mat.roughness = 0.18
	_facade_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_facade_lit_mat = StandardMaterial3D.new()
	_facade_lit_mat.albedo_color = Color(1.0, 0.82, 0.56)
	_facade_lit_mat.emission_enabled = true
	_facade_lit_mat.emission = Color(1.0, 0.72, 0.36)
	_facade_lit_mat.emission_energy_multiplier = 0.7
	_facade_lit_mat.roughness = 0.36

	_roof_mat = StandardMaterial3D.new()
	_roof_mat.albedo_color = Color(0.4, 0.41, 0.45)
	_roof_mat.roughness = 0.95
	_palm_trunk_mesh = TreeMesh.to_mesh(TreeMesh.palm_trunk(9.0))
	_palm_crown_mesh = TreeMesh.to_mesh(TreeMesh.palm_crown(11, 3.0, 9.0))
	_palm_bark_mat = StandardMaterial3D.new()
	_palm_bark_mat.albedo_color = Color(0.55, 0.47, 0.36)
	_palm_bark_mat.roughness = 0.9
	_palm_frond_mat = StandardMaterial3D.new()
	_palm_frond_mat.albedo_color = Color(0.30, 0.49, 0.22)
	_palm_frond_mat.roughness = 0.85
	_palm_frond_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_palm_frond_mat.backlight = Color(0.10, 0.16, 0.07)
	_parked_coupe_mesh = VehicleVisualLibrary.traffic_mesh(VehicleVisualLibrary.Variant.SPORT_COUPE)
	_parked_sedan_mesh = VehicleVisualLibrary.traffic_mesh(
		VehicleVisualLibrary.Variant.CLASSIC_SEDAN
	)
	_make_rooftop_resources()


func _make_rooftop_resources() -> void:
	var ac_mat := StandardMaterial3D.new()
	ac_mat.albedo_color = Color(0.5, 0.51, 0.54)
	ac_mat.metallic = 0.5
	ac_mat.roughness = 0.5
	var tank_mat := StandardMaterial3D.new()
	tank_mat.albedo_color = Color(0.4, 0.36, 0.3)
	tank_mat.roughness = 0.85
	var house_mat := StandardMaterial3D.new()
	house_mat.albedo_color = Color(0.42, 0.43, 0.45)
	house_mat.roughness = 0.8
	var mast_mat := StandardMaterial3D.new()
	mast_mat.albedo_color = Color(0.12, 0.12, 0.13)
	mast_mat.metallic = 0.7
	mast_mat.roughness = 0.45
	var beacon_mat := StandardMaterial3D.new()
	beacon_mat.albedo_color = Color(0.9, 0.1, 0.08)
	beacon_mat.emission_enabled = true
	beacon_mat.emission = Color(1.0, 0.12, 0.06)
	beacon_mat.emission_energy_multiplier = 3.0
	_rooftop_materials.assign([ac_mat, tank_mat, house_mat, mast_mat, beacon_mat])

	var ac_mesh := BoxMesh.new()
	ac_mesh.size = Vector3(2.6, 1.2, 2.0)
	var tank_mesh := CylinderMesh.new()
	tank_mesh.top_radius = 1.1
	tank_mesh.bottom_radius = 1.1
	tank_mesh.height = 2.2
	var house_mesh := BoxMesh.new()
	house_mesh.size = Vector3.ONE
	var mast_mesh := CylinderMesh.new()
	mast_mesh.top_radius = 0.1
	mast_mesh.bottom_radius = 0.22
	mast_mesh.height = 1.0
	var beacon_mesh := SphereMesh.new()
	beacon_mesh.radius = 0.32
	beacon_mesh.height = 0.64
	_rooftop_meshes.assign([ac_mesh, tank_mesh, house_mesh, mast_mesh, beacon_mesh])


## Assign a tileable detail albedo onto a shader material's `detail_tex` uniform,
## if the shader uses one and the texture exists (no-op on the greybox fallback).
static func _set_detail_texture(mat: Material, tex_path: String) -> void:
	if mat is ShaderMaterial and ResourceLoader.exists(tex_path):
		(mat as ShaderMaterial).set_shader_parameter("detail_tex", load(tex_path))


static func _shader_or_fallback(path: String, fallback: Color) -> Material:
	var shader := load(path) as Shader
	if shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		return mat
	var std := StandardMaterial3D.new()
	std.albedo_color = fallback
	std.roughness = 0.9
	# Double-sided keeps interiors lit if a footprint winds oddly.
	std.cull_mode = BaseMaterial3D.CULL_DISABLED
	return std
