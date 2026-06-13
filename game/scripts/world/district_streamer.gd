extends Node3D
## Streams real-world districts and their prepared 128 m tiles around the player.
##
## District selection and tile ordering are pure/tested. JSON parsing and mesh
## array generation run on district worker threads; this coordinator performs at
## most one bounded SceneTree operation per physics frame across the whole world.

const DistrictLoaderScript := preload("res://scripts/world/district_loader.gd")

@export_file("*.json") var manifest_path: String = "res://assets/world/districts.json"
@export var streaming_enabled: bool = true
@export var load_radius: float = 1600.0
@export var unload_radius: float = 2400.0
@export var update_interval: float = 0.25
@export var tile_size: float = 128.0
@export var near_tile_radius: float = 900.0
@export var near_tile_unload_radius: float = 1100.0
@export_range(1, 8, 1) var max_loads_per_update: int = 1

var _districts: Array = []
var _district_by_name: Dictionary = {}
var _resident: Dictionary = {}
var _load_queue: Array[String] = []
var _unload_queue: Array[String] = []
var _accum: float = 0.0
var _last_camera: Vector2 = Vector2.ZERO
var _observed_velocity: Vector2 = Vector2.ZERO
var _started_usec: int = 0
var _initial_load_ms: float = 0.0
var _max_main_thread_step_ms: float = 0.0
var _max_main_thread_step_kind: String = ""
var _max_tile_commit_ms: float = 0.0
var _max_tile_commit_kind: String = ""
var _operations_this_frame: int = 0
var _peak_operations_per_frame: int = 0
var _district_loads_total: int = 0
var _district_unloads_total: int = 0


func _ready() -> void:
	add_to_group("district_streamer")
	_started_usec = Time.get_ticks_usec()
	if not streaming_enabled:
		return
	var manifest := _load(manifest_path)
	for source: Dictionary in manifest.get("districts", []):
		var offset: Dictionary = source.get("world_offset", {"x": 0, "z": 0})
		var district := {
			"name": str(source["name"]),
			"data": str(source["data"]),
			"offset": Vector2(float(offset["x"]), float(offset["z"])),
		}
		_districts.append(district)
		_district_by_name[district["name"]] = district
	_last_camera = _camera_xz()
	_update()
	_stream_one_operation(Vector3(_last_camera.x, 0.0, _last_camera.y), Vector3.ZERO)


## Sorted-on-read by the HUD; presence in the dict means loading or resident.
func resident_names() -> Array:
	return _resident.keys()


func district_count() -> int:
	return _districts.size()


func stats() -> Dictionary:
	var tiles_total := 0
	var tiles_resident := 0
	var tiles_pending := 0
	var background_build_ms := 0.0
	for loader: Node in _resident.values():
		if not loader.has_method("streaming_stats"):
			continue
		var loader_stats: Dictionary = loader.call("streaming_stats")
		tiles_total += int(loader_stats["tiles_total"])
		tiles_resident += int(loader_stats["tiles_resident"])
		tiles_pending += int(loader_stats["tiles_pending"])
		background_build_ms = maxf(background_build_ms, float(loader_stats["background_build_ms"]))
	return {
		"resident": _resident.size(),
		"loading": _load_queue.size(),
		"district_loads_total": _district_loads_total,
		"district_unloads_total": _district_unloads_total,
		"tiles_total": tiles_total,
		"tiles_resident": tiles_resident,
		"tiles_pending": tiles_pending,
		"initial_load_ms": _initial_load_ms,
		"background_build_ms": background_build_ms,
		"max_main_thread_step_ms": _max_main_thread_step_ms,
		"max_main_thread_step_kind": _max_main_thread_step_kind,
		"max_tile_commit_ms": _max_tile_commit_ms,
		"max_tile_commit_kind": _max_tile_commit_kind,
		"peak_operations_per_frame": _peak_operations_per_frame,
	}


func _physics_process(delta: float) -> void:
	_operations_this_frame = 0
	var camera := _camera_xz()
	if delta > 0.0:
		_observed_velocity = (camera - _last_camera) / delta
	_last_camera = camera
	_accum += delta
	if _accum >= update_interval:
		_accum = 0.0
		_update()
	_stream_one_operation(
		Vector3(camera.x, 0.0, camera.y), Vector3(_observed_velocity.x, 0.0, _observed_velocity.y)
	)
	_peak_operations_per_frame = maxi(_peak_operations_per_frame, _operations_this_frame)


func _update() -> void:
	var decision := Streaming.resolve(
		_last_camera, _districts, load_radius, unload_radius, _resident, _observed_velocity
	)
	_load_queue.assign(decision["to_load"])
	_unload_queue.assign(decision["to_unload"])


func _stream_one_operation(observer: Vector3, velocity: Vector3) -> void:
	if not _unload_queue.is_empty():
		_unload(_unload_queue.pop_front())
		_operations_this_frame = 1
		return
	if not _load_queue.is_empty():
		_load_district(_load_queue.pop_front())
		_operations_this_frame = 1
		return

	var ordered_names: Array[String] = []
	for name: String in _resident:
		ordered_names.append(name)
	ordered_names.sort_custom(
		func(a: String, b: String) -> bool:
			var da: Vector2 = _district_by_name[a]["offset"]
			var db: Vector2 = _district_by_name[b]["offset"]
			var origin := Vector2(observer.x, observer.z)
			return origin.distance_squared_to(da) < origin.distance_squared_to(db)
	)
	for name: String in ordered_names:
		var loader: Node = _resident[name]
		if loader.call("stream_one_step", observer, velocity):
			_operations_this_frame = 1
			if _initial_load_ms <= 0.0:
				var loader_stats: Dictionary = loader.call("streaming_stats")
				if int(loader_stats["tiles_resident"]) > 0:
					_initial_load_ms = float(Time.get_ticks_usec() - _started_usec) / 1000.0
			return


func _camera_xz() -> Vector2:
	for player: Node in get_tree().get_nodes_in_group("player"):
		if player is Node3D:
			var position := (player as Node3D).global_position
			return Vector2(position.x, position.z)
	return Vector2.ZERO


func _load_district(name: String) -> void:
	if _resident.has(name) or not _district_by_name.has(name):
		return
	var district: Dictionary = _district_by_name[name]
	var node := Node3D.new()
	node.name = "District_%s" % name
	node.set_script(DistrictLoaderScript)
	node.set("district_path", district["data"])
	node.set("tile_size", tile_size)
	node.set("near_radius", near_tile_radius)
	node.set("near_unload_radius", near_tile_unload_radius)
	node.set("place_player", _resident.is_empty())
	node.connect("streaming_step", _on_streaming_step)
	add_child(node)
	_resident[name] = node
	_district_loads_total += 1


func _unload(name: String) -> void:
	if not _resident.has(name):
		return
	(_resident[name] as Node).queue_free()
	_resident.erase(name)
	_district_unloads_total += 1


func _on_streaming_step(duration_ms: float, kind: String) -> void:
	if duration_ms > _max_main_thread_step_ms:
		_max_main_thread_step_ms = duration_ms
		_max_main_thread_step_kind = kind
	if kind.begins_with("tile_") and duration_ms > _max_tile_commit_ms:
		_max_tile_commit_ms = duration_ms
		_max_tile_commit_kind = kind


func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
