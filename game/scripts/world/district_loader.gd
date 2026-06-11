extends Node3D
## Builds a real-world city district from a normalized OSM data file
## (produced by tools/osm/fetch_district.py). Reads building footprints and road
## polylines, projects them into local metres via GeoProjection, and assembles
## batched meshes via CityBuilder. All heavy geometry math lives in those tested
## helpers; this node only orchestrates scene assembly.
##
## Buildings merge into one MeshInstance3D + one trimesh collider so the player
## and vehicles collide with the skyline; roads merge into a single flat,
## collision-free ribbon mesh laid just above the ground plane.

signal district_built(building_count: int, road_count: int)

const WINDOW_SHADER := preload("res://assets/materials/building_windows.gdshader")

## Streetlight pole every ~this many metres of road, capped scene-wide and
## kept near the district origin (where the player spawns) so the cap is not
## eaten by far-away roads.
const STREETLIGHT_SPACING_M: float = 45.0
const MAX_STREETLIGHTS: int = 60
const STREETLIGHT_RADIUS_M: float = 250.0

## res:// path to the district JSON (OSM-derived, ODbL).
@export_file("*.json") var district_path: String = "res://assets/world/downtown_la.json"
## Build collision for buildings. Off speeds up pure-visual previews.
@export var build_collision: bool = true
## Spawn streetlight poles along roads (toggled at night by TimeOfDay).
@export var build_streetlights: bool = true

var _building_mat: ShaderMaterial
var _roof_mat: StandardMaterial3D
var _road_mat: StandardMaterial3D


func _ready() -> void:
	# TimeOfDay fades our building-window glow through set_night_amount().
	add_to_group("night_emissive")
	_make_materials()
	var data := _load_district(district_path)
	if data.is_empty():
		push_error("district_loader: could not load %s" % district_path)
		return

	var origin: Dictionary = data["origin"]
	var proj := GeoProjection.new(origin["lat"], origin["lon"])

	var built_buildings := _build_buildings(data.get("buildings", []), proj)
	_build_roads(data.get("roads", []), proj)
	if build_streetlights:
		_build_streetlights(data.get("roads", []), proj)
	_place_actors_on_street(data.get("roads", []), proj)

	var nb: int = (data.get("buildings", []) as Array).size()
	var nr: int = (data.get("roads", []) as Array).size()
	print(
		(
			"district_loader: built %s — %d buildings (%d meshed), %d roads"
			% [data.get("name", "district"), nb, built_buildings, nr]
		)
	)
	district_built.emit(nb, nr)


func _load_district(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


## Merge a geometry dict into accumulator arrays, offsetting indices.
static func _append_geo(
	verts: PackedVector3Array, norms: PackedVector3Array, idx: PackedInt32Array, geo: Dictionary
) -> void:
	if geo.is_empty():
		return
	var offset := verts.size()
	verts.append_array(geo["vertices"])
	norms.append_array(geo["normals"])
	for i in geo["indices"] as PackedInt32Array:
		idx.append(offset + i)


func _project_ring(raw: Array, proj: GeoProjection) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for pair in raw:
		ring.append(proj.to_local_2d(pair[0], pair[1]))
	return ring


func _build_buildings(buildings: Array, proj: GeoProjection) -> int:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var meshed := 0

	for b in buildings:
		var ring := _project_ring(b["footprint"], proj)
		var geo := CityBuilder.extrude_prism(ring, 0.0, float(b["height_m"]))
		if geo.is_empty():
			continue
		_append_geo(verts, norms, idx, geo)
		meshed += 1

	if verts.is_empty():
		return 0

	var mesh := CityBuilder.arrays_to_mesh({"vertices": verts, "normals": norms, "indices": idx})
	mesh.surface_set_material(0, _building_mat)
	var mi := MeshInstance3D.new()
	mi.name = "Buildings"
	mi.mesh = mesh
	add_child(mi)
	if build_collision:
		mi.create_trimesh_collision()
	return meshed


func _build_roads(roads: Array, proj: GeoProjection) -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()

	for r in roads:
		var path := _project_ring(r["path"], proj)
		var geo := CityBuilder.road_ribbon(path, float(r["width_m"]), 0.05)
		_append_geo(verts, norms, idx, geo)

	if verts.is_empty():
		return
	var mesh := CityBuilder.arrays_to_mesh({"vertices": verts, "normals": norms, "indices": idx})
	mesh.surface_set_material(0, _road_mat)
	var mi := MeshInstance3D.new()
	mi.name = "Roads"
	mi.mesh = mesh
	add_child(mi)


## Plant streetlight poles along road kerbs: shared pole mesh, one warm
## shadowless OmniLight3D each, all in group "streetlight" so TimeOfDay can
## hard-toggle them with hysteresis. Capped so the light count stays cheap.
func _build_streetlights(roads: Array, proj: GeoProjection) -> void:
	var holder := Node3D.new()
	holder.name = "StreetLights"
	add_child(holder)

	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.08
	pole_mesh.bottom_radius = 0.12
	pole_mesh.height = 5.0
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.18, 0.19, 0.21)
	pole_mat.roughness = 0.7
	pole_mesh.material = pole_mat

	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.16
	bulb_mesh.height = 0.32
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.82, 0.5)
	bulb_mat.emission_energy_multiplier = 4.0
	bulb_mesh.material = bulb_mat

	var count := 0
	for r in roads:
		if count >= MAX_STREETLIGHTS:
			break
		var kerb := float(r["width_m"]) * 0.5 + 0.8
		var spots := DaylightMath.spaced_along(
			_project_ring(r["path"], proj), STREETLIGHT_SPACING_M, kerb
		)
		for spot in spots:
			if count >= MAX_STREETLIGHTS:
				break
			if spot.length() > STREETLIGHT_RADIUS_M:
				continue
			var pole := MeshInstance3D.new()
			pole.mesh = pole_mesh
			pole.position = Vector3(spot.x, 2.5, spot.y)
			holder.add_child(pole)

			var lamp := OmniLight3D.new()
			lamp.position = Vector3(0.0, 2.6, 0.0)
			lamp.light_color = Color(1.0, 0.82, 0.5)
			lamp.light_energy = 2.0
			lamp.omni_range = 18.0
			lamp.shadow_enabled = false
			lamp.visible = false
			lamp.add_to_group("streetlight")
			pole.add_child(lamp)

			var bulb := MeshInstance3D.new()
			bulb.mesh = bulb_mesh
			lamp.add_child(bulb)
			count += 1


## TimeOfDay (group "night_emissive") fades building windows in/out, 0..1.
func set_night_amount(amount: float) -> void:
	if _building_mat != null:
		_building_mat.set_shader_parameter("night_amount", amount)


## Move the player + spawn marker onto the road vertex nearest the origin so the
## player never starts trapped inside a building footprint.
func _place_actors_on_street(roads: Array, proj: GeoProjection) -> void:
	var best := Vector3.ZERO
	var best_dist := INF
	for r in roads:
		for pair in r["path"]:
			var p := proj.to_local(pair[0], pair[1])
			var d := p.length()
			if d < best_dist:
				best_dist = d
				best = p
	best.y = 1.0

	var tree := get_tree()
	if tree == null:
		return
	for marker in tree.get_nodes_in_group("spawn_points"):
		if marker is Node3D:
			(marker as Node3D).global_position = best
	for player in tree.get_nodes_in_group("player"):
		if player is Node3D:
			(player as Node3D).global_position = best + Vector3(0, 0.5, 0)


func _make_materials() -> void:
	# Buildings use the procedural window shader (object-space grid, double-
	# sided via render_mode) so TimeOfDay can glow the windows at night.
	_building_mat = ShaderMaterial.new()
	_building_mat.shader = WINDOW_SHADER

	_roof_mat = StandardMaterial3D.new()
	_roof_mat.albedo_color = Color(0.4, 0.41, 0.45)
	_roof_mat.roughness = 0.95

	_road_mat = StandardMaterial3D.new()
	_road_mat.albedo_color = Color(0.16, 0.16, 0.19)
	_road_mat.roughness = 1.0
