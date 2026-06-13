extends Node3D
## Streams real-world districts in and out around the player using the world
## manifest. Each district's geometry is already authored in shared world
## coordinates (every district projects against the same origin), so loading one
## is just instancing a DistrictLoader pointed at its JSON — it lands at its true
## position automatically. This is the M3 foundation that lets the whole of LA
## exist without loading every tile at once.
##
## Decision logic is in Streaming.resolve (tested); this node only applies it.

const DistrictLoaderScript := preload("res://scripts/world/district_loader.gd")

@export_file("*.json") var manifest_path: String = "res://assets/world/districts.json"
@export var load_radius: float = 1600.0
@export var unload_radius: float = 2400.0
@export var update_interval: float = 0.5

var _districts: Array = []
var _resident: Dictionary = {}
var _accum: float = 0.0


func _ready() -> void:
	add_to_group("district_streamer")
	var manifest := _load(manifest_path)
	for d in manifest.get("districts", []):
		var off: Dictionary = d.get("world_offset", {"x": 0, "z": 0})
		(
			_districts
			. append(
				{
					"name": d["name"],
					"data": d["data"],
					"offset": Vector2(off["x"], off["z"]),
				}
			)
		)
	_update()  # resolve once on spawn so the starting district is present immediately


## Sorted-on-read by the HUD; presence in the dict means loaded.
func resident_names() -> Array:
	return _resident.keys()


func district_count() -> int:
	return _districts.size()


func _physics_process(delta: float) -> void:
	_accum += delta
	if _accum < update_interval:
		return
	_accum = 0.0
	_update()


func _update() -> void:
	var cam := _camera_xz()
	var decision := Streaming.resolve(cam, _districts, load_radius, unload_radius, _resident)
	for name in decision["to_unload"]:
		_unload(name)
	for name in decision["to_load"]:
		_load_district(name)


func _camera_xz() -> Vector2:
	for p in get_tree().get_nodes_in_group("player"):
		if p is Node3D:
			var pos := (p as Node3D).global_position
			# District offsets are absolute world coordinates; under a
			# FloatingOrigin the engine-local position must be converted back.
			var origin := get_tree().get_first_node_in_group("floating_origin") as FloatingOrigin
			if origin != null:
				pos = OriginMath.to_absolute(pos, origin.origin_offset)
			return Vector2(pos.x, pos.z)
	return Vector2.ZERO


func _load_district(name: String) -> void:
	for d in _districts:
		if d["name"] != name:
			continue
		var node := Node3D.new()
		node.name = "District_%s" % name
		node.set_script(DistrictLoaderScript)
		node.set("district_path", d["data"])
		# The FIRST district to page in owns spawn: it snaps the player onto its
		# nearest street so they don't start buried inside a building at the fixed
		# scene spawn point. Later districts leave the player where they are.
		node.set("place_player", _resident.is_empty())
		add_child(node)
		_resident[name] = node
		return


func _unload(name: String) -> void:
	if _resident.has(name):
		(_resident[name] as Node).queue_free()
		_resident.erase(name)


func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
