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

## Streetlight pole every ~this many metres of road, capped scene-wide and
## kept near the district origin (where the player spawns) so the cap is not
## eaten by far-away roads.
const STREETLIGHT_SPACING_M: float = 45.0
const MAX_STREETLIGHTS: int = 60
const STREETLIGHT_RADIUS_M: float = 250.0
## Real warm OmniLight3D pools hung under the lamp heads, faded in at night by
## the StreetlightSwitch. Capped below the pole count and shadowless so the
## streets actually glow without paying a shadow map per lamp; range/energy tuned
## for a soft on-ground pool cast from the ~5 m head.
const MAX_STREETLIGHT_LIGHTS: int = 100
const STREETLIGHT_LIGHT_RANGE_M: float = 13.0
const STREETLIGHT_LIGHT_ENERGY: float = 4.0
## Visual walking surfaces sit just under the ground collider top
## (GROUND_SURFACE_Y) so the player rests flush on the street; the spawn vista's
## hero road aligns to STREET_VISUAL_Y (see DistrictSpawnVista).
const STREET_VISUAL_Y: float = 0.32
const SIDEWALK_VISUAL_Y: float = 0.28
const GROUND_SURFACE_Y: float = 0.4
## Footprints extruded per build slice. Sized so one slice stays a small
## fraction of a 60 Hz frame; a 1500-building district pages in across ~7
## slices instead of one giant hitch.
const BUILDINGS_PER_SLICE: int = 220

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

var _building_mat: Material
var _facade_glass_mat: StandardMaterial3D
var _facade_lit_mat: StandardMaterial3D
var _roof_mat: StandardMaterial3D
var _road_mat: Material
var _sidewalk_mat: Material


func _ready() -> void:
	# TimeOfDay fades our building-window glow through set_night_amount().
	add_to_group("night_emissive")
	_make_materials()
	var data := _load_district(district_path)
	if data.is_empty():
		push_error("district_loader: could not load %s" % district_path)
		return
	_build_timesliced(data)


## Assemble the district one stage per frame: ground, building slices, the
## welded building mesh + collider, then each road/prop pass. Paging a district
## in mid-drive costs many small frames instead of one long stall. Every stage
## re-checks the loader is still in the tree, so a district unloaded mid-build
## stops cleanly instead of building into a freed branch.
func _build_timesliced(data: Dictionary) -> void:
	var origin: Dictionary = data["origin"]
	var proj := GeoProjection.new(origin["lat"], origin["lon"])
	var buildings: Array = data.get("buildings", [])
	var roads: Array = data.get("roads", [])
	var tree := get_tree()

	if spawn_ground:
		_build_ground(data, proj)

	# Buildings: extrude footprints a slice per frame, then weld once into a
	# single MeshInstance3D + trimesh collider (one draw call, as before).
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var colors := PackedColorArray()
	var meshed := 0
	var cursor := 0
	while cursor < buildings.size():
		if not await _next_stage(tree):
			return
		var slice_end := mini(cursor + BUILDINGS_PER_SLICE, buildings.size())
		while cursor < slice_end:
			var b: Dictionary = buildings[cursor]
			cursor += 1
			var ring := _project_ring(b["footprint"], proj)
			var geo := CityBuilder.extrude_prism(ring, 0.0, float(b["height_m"]))
			if geo.is_empty():
				continue
			_append_geo(verts, norms, idx, geo)
			# Per-building wall tint, read by the facade shader as vertex COLOR.
			var bid := int(b.get("id", meshed))
			var tint := CityBuilder.building_color(bid)
			# Glassiness seed packed into vertex-colour alpha: tall buildings
			# bias toward reflective glass curtain-wall, short toward masonry.
			tint.a = CityBuilder.building_glass_seed(bid, float(b["height_m"]))
			for _i in (geo["vertices"] as PackedVector3Array).size():
				colors.append(tint)
			meshed += 1
	if not await _next_stage(tree):
		return
	_commit_buildings(verts, norms, idx, colors)

	# Remaining passes, one per frame.
	var stages: Array[Callable] = [
		func() -> void: DistrictFacadePanels.build(self, buildings, proj),
		func() -> void: _build_rooftops(buildings, proj),
		func() -> void: _build_roads(roads, proj),
		func() -> void: _build_sidewalks(roads, proj),
	]
	if build_doors:
		stages.append(func() -> void: BuildingDoors.build(self, buildings, proj))
		stages.append(func() -> void: BuildingShops.build(self, buildings, proj))
	if build_streetlights:
		stages.append(func() -> void: _build_streetlights(roads, proj))
	stages.append(func() -> void: _build_palms(roads, proj))
	stages.append(func() -> void: _build_parked_cars(roads, proj))
	stages.append(func() -> void: _build_trees(roads, proj))
	stages.append(func() -> void: _build_street_furniture(roads, proj))
	if place_player:
		stages.append(func() -> void: _place_player_stage(data, proj))
	for stage in stages:
		if not await _next_stage(tree):
			return
		stage.call()

	district_built.emit(buildings.size(), roads.size())


func _place_player_stage(data: Dictionary, proj: GeoProjection) -> void:
	var origin: Dictionary = data["origin"]
	var centre_geo: Dictionary = data.get("centroid", origin)
	var centre := proj.to_local(centre_geo["lat"], centre_geo["lon"])
	_place_actors_on_street(data.get("roads", []), data.get("buildings", []), proj, centre)


# One frame boundary between build stages; false once the loader has left the
# tree (district unloaded mid-build) so the rest of the build must not run.
func _next_stage(tree: SceneTree) -> bool:
	await tree.process_frame
	return is_inside_tree()


## Break up the flat-topped skyline with rooftop superstructure: mechanical
## penthouses (scaled boxes) on mid/high-rises, water tanks + AC condensers on
## the rest, and antenna masts capped with a red aircraft-warning beacon on the
## genuine towers. Everything batches into a handful of MultiMesh draw calls
## (one per prop type) so hundreds of props cost almost nothing.
func _build_rooftops(buildings: Array, proj: GeoProjection) -> void:
	var ac_tf: Array[Transform3D] = []
	var tank_tf: Array[Transform3D] = []
	var house_tf: Array[Transform3D] = []
	var mast_tf: Array[Transform3D] = []
	var beacon_tf: Array[Transform3D] = []

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var placed := 0
	for b in buildings:
		if placed >= 650:
			break
		var height := float(b.get("height_m", 0.0))
		if height < 6.0:
			continue
		var ring := _project_ring(b["footprint"], proj)
		if ring.size() < 3:
			continue
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		var centre := Vector2.ZERO
		for p in ring:
			centre += p
			mn = mn.min(p)
			mx = mx.max(p)
		centre /= float(ring.size())
		var ext := mx - mn  # footprint extent (metres) in x/z
		var roof := Vector3(centre.x, height, centre.y)

		# Mechanical penthouse — a smaller box, sized to a fraction of the roof,
		# is the single biggest break to the dead-flat silhouette from afar.
		if height >= 22.0 and ext.x > 6.0 and ext.y > 6.0:
			var phx := clampf(ext.x * rng.randf_range(0.3, 0.5), 3.0, 16.0)
			var phz := clampf(ext.y * rng.randf_range(0.3, 0.5), 3.0, 16.0)
			var phh := rng.randf_range(3.0, 6.0)
			var off := Vector3(rng.randf_range(-1.5, 1.5), 0.0, rng.randf_range(-1.5, 1.5))
			house_tf.append(
				Transform3D(
					Basis.from_scale(Vector3(phx, phh, phz)), roof + off + Vector3(0, phh * 0.5, 0)
				)
			)

		# Antenna mast + always-on red beacon on the real high-rises; a water tank
		# on mid-rises; a small stair/elevator bulkhead on the low-rise Deco roofs
		# so even the two-storey hotels aren't bare flat boxes.
		if height >= 50.0:
			var mh := rng.randf_range(8.0, 18.0)
			mast_tf.append(
				Transform3D(Basis.from_scale(Vector3(1, mh, 1)), roof + Vector3(0, mh * 0.5, 0))
			)
			beacon_tf.append(Transform3D(Basis.IDENTITY, roof + Vector3(0, mh, 0)))
		elif height >= 12.0:
			tank_tf.append(
				Transform3D(
					Basis.IDENTITY,
					roof + Vector3(rng.randf_range(-2.5, 2.5), 1.1, rng.randf_range(-2.5, 2.5))
				)
			)
		elif ext.x > 4.0 and ext.y > 4.0:
			var bw := clampf(minf(ext.x, ext.y) * rng.randf_range(0.25, 0.4), 2.0, 5.0)
			var bh := rng.randf_range(1.8, 2.8)
			house_tf.append(
				Transform3D(
					Basis.from_scale(Vector3(bw, bh, bw)),
					roof + Vector3(rng.randf_range(-1.0, 1.0), bh * 0.5, rng.randf_range(-1.0, 1.0))
				)
			)

		# AC condenser on (almost) every roof, randomly yawed.
		var ac_basis := Basis(Vector3.UP, rng.randf() * TAU)
		ac_tf.append(
			Transform3D(
				ac_basis, roof + Vector3(rng.randf_range(-3, 3), 0.6, rng.randf_range(-3, 3))
			)
		)
		placed += 1

	var container := Node3D.new()
	container.name = "Rooftops"
	add_child(container)

	var tank_mat := StandardMaterial3D.new()
	tank_mat.albedo_color = Color(0.4, 0.36, 0.3)
	tank_mat.roughness = 0.85
	var ac_mat := StandardMaterial3D.new()
	ac_mat.albedo_color = Color(0.5, 0.51, 0.54)
	ac_mat.metallic = 0.5
	ac_mat.roughness = 0.5
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

	var tank_mesh := CylinderMesh.new()
	tank_mesh.top_radius = 1.1
	tank_mesh.bottom_radius = 1.1
	tank_mesh.height = 2.2
	var ac_mesh := BoxMesh.new()
	ac_mesh.size = Vector3(2.6, 1.2, 2.0)
	var house_mesh := BoxMesh.new()  # unit box, scaled per instance
	house_mesh.size = Vector3.ONE
	var mast_mesh := CylinderMesh.new()  # unit-height, scaled per instance
	mast_mesh.top_radius = 0.1
	mast_mesh.bottom_radius = 0.22
	mast_mesh.height = 1.0
	var beacon_mesh := SphereMesh.new()
	beacon_mesh.radius = 0.32
	beacon_mesh.height = 0.64

	_rooftop_layer("ACUnits", ac_mesh, ac_mat, ac_tf, container)
	_rooftop_layer("WaterTanks", tank_mesh, tank_mat, tank_tf, container)
	_rooftop_layer("Penthouses", house_mesh, house_mat, house_tf, container)
	_rooftop_layer("Masts", mast_mesh, mast_mat, mast_tf, container)
	_rooftop_layer("Beacons", beacon_mesh, beacon_mat, beacon_tf, container)


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


## Sprinkle sidewalk furniture — trash bins and fire hydrants — along the kerb of
## the wider roads. Orientation-free props (rotationally symmetric), so no road
## tangent is needed; shared meshes/materials and a hard cap keep it cheap.
func _build_street_furniture(roads: Array, proj: GeoProjection) -> void:
	var bin_mat := StandardMaterial3D.new()
	bin_mat.albedo_color = Color(0.16, 0.28, 0.2)
	bin_mat.metallic = 0.3
	bin_mat.roughness = 0.6
	var hydrant_mat := StandardMaterial3D.new()
	hydrant_mat.albedo_color = Color(0.7, 0.13, 0.1)
	hydrant_mat.roughness = 0.5
	var bin_mesh := CylinderMesh.new()
	bin_mesh.top_radius = 0.2
	bin_mesh.bottom_radius = 0.22
	bin_mesh.height = 0.66
	var hydrant_mesh := CylinderMesh.new()
	hydrant_mesh.top_radius = 0.11
	hydrant_mesh.bottom_radius = 0.12
	hydrant_mesh.height = 0.42
	var hydrant_cap := SphereMesh.new()
	hydrant_cap.radius = 0.12
	hydrant_cap.height = 0.18

	var container := Node3D.new()
	container.name = "StreetFurniture"
	container.position.y = 0.15  # sit props on the raised sidewalk, not the gutter
	add_child(container)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var placed := 0
	for r in roads:
		if placed >= 70:
			break
		if float(r.get("width_m", 0.0)) < 8.0:
			continue
		var path := _project_ring(r["path"], proj)
		for p in StreetLight.sample_along(path, 38.0, float(r["width_m"]) * 0.5 + 1.5):
			if placed >= 70:
				break
			var prop := Node3D.new()
			prop.position = Vector3(p.x, 0.0, p.y)
			if rng.randf() < 0.85:
				_add_mesh(prop, bin_mesh, Vector3(0.0, 0.33, 0.0), bin_mat)
			else:
				_add_mesh(prop, hydrant_mesh, Vector3(0.0, 0.21, 0.0), hydrant_mat)
				_add_mesh(prop, hydrant_cap, Vector3(0.0, 0.42, 0.0), hydrant_mat)
			container.add_child(prop)
			placed += 1
	LodUtil.apply_range(container, 120.0)


func _add_mesh(parent: Node, mesh: Mesh, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


## Scatter street trees on the setback behind the kerb of the wider roads, with
## per-tree scale and yaw variety. Shares one trunk + one canopy mesh across all
## trees and caps the count, so a whole green avenue costs almost nothing.
func _build_trees(roads: Array, proj: GeoProjection) -> void:
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.32, 0.23, 0.16)
	bark.roughness = 0.95
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.21, 0.42, 0.18)
	leaf.roughness = 0.9
	leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	var trunk_mesh := TreeMesh.to_mesh(TreeMesh.trunk())
	var canopy_mesh := TreeMesh.to_mesh(TreeMesh.canopy())

	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var container := Node3D.new()
	container.name = "Trees"
	add_child(container)

	var placed := 0
	for r in roads:
		if placed >= 55:
			break
		if float(r.get("width_m", 0.0)) < 9.0:
			continue
		var path := _project_ring(r["path"], proj)
		for p in StreetLight.sample_along(path, 36.0, float(r["width_m"]) * 0.5 + 2.6):
			if placed >= 55:
				break
			var tree := Node3D.new()
			tree.position = Vector3(p.x, 0.0, p.y)
			var scale_factor := rng.randf_range(0.8, 1.25)
			tree.scale = Vector3(scale_factor, scale_factor, scale_factor)
			tree.rotation.y = rng.randf() * TAU
			var trunk := MeshInstance3D.new()
			trunk.mesh = trunk_mesh
			trunk.material_override = bark
			tree.add_child(trunk)
			var crown := MeshInstance3D.new()
			crown.mesh = canopy_mesh
			crown.material_override = leaf
			crown.position = Vector3(0.0, 3.9, 0.0)
			tree.add_child(crown)
			container.add_child(tree)
			placed += 1
	LodUtil.apply_range(container, 300.0)


## Palm-lined avenues — the signature Miami streetscape. Trunks and frond crowns
## are two MultiMeshes sharing one per-instance transform list, so hundreds of
## palms cost two draw calls. The crown mesh is authored at the trunk top so the
## same transform places both. Denser + on more roads than the broadleaf trees.
func _build_palms(roads: Array, proj: GeoProjection) -> void:
	var trunk_mesh := TreeMesh.to_mesh(TreeMesh.palm_trunk(9.0))
	var crown_mesh := TreeMesh.to_mesh(TreeMesh.palm_crown(11, 3.0, 9.0))
	if trunk_mesh == null or crown_mesh == null:
		return
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.55, 0.47, 0.36)  # pale grey-brown palm bark
	bark.roughness = 0.9
	var frond := StandardMaterial3D.new()
	frond.albedo_color = Color(0.30, 0.49, 0.22)  # tropical frond green
	frond.roughness = 0.85
	frond.cull_mode = BaseMaterial3D.CULL_DISABLED
	frond.backlight = Color(0.10, 0.16, 0.07)  # soft leaf translucency in sun

	var rng := RandomNumberGenerator.new()
	rng.seed = 9151
	var transforms: Array[Transform3D] = []
	for r in roads:
		if transforms.size() >= 900:
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
				if transforms.size() >= 900:
					break
				var s := rng.randf_range(0.82, 1.3)
				var basis := Basis.from_euler(Vector3(0.0, rng.randf() * TAU, 0.0)).scaled(
					Vector3(s, s, s)
				)
				transforms.append(Transform3D(basis, Vector3(p.x, 0.0, p.y)))

	if transforms.is_empty():
		return
	_add_palm_layer(trunk_mesh, bark, transforms, "PalmTrunks")
	_add_palm_layer(crown_mesh, frond, transforms, "PalmCrowns")


func _add_palm_layer(
	mesh: Mesh, mat: Material, transforms: Array[Transform3D], node_name: String
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
	add_child(mmi)


## Parked cars line the kerbs using decimated versions of the production coupe
## and sedan, batched into one MultiMesh per model. They have no AI or physics;
## moving traffic is populated separately by TrafficDirector.
func _build_parked_cars(roads: Array, proj: GeoProjection) -> void:
	const PARKED_CAR_LIMIT: int = 240
	const PARKED_CAR_SPACING: float = 14.0
	var coupe_mesh := VehicleVisualLibrary.traffic_mesh(VehicleVisualLibrary.Variant.SPORT_COUPE)
	var sedan_mesh := VehicleVisualLibrary.traffic_mesh(VehicleVisualLibrary.Variant.CLASSIC_SEDAN)
	if coupe_mesh == null or sedan_mesh == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 2207
	var coupe_transforms: Array[Transform3D] = []
	var sedan_transforms: Array[Transform3D] = []
	for r in roads:
		if coupe_transforms.size() + sedan_transforms.size() >= PARKED_CAR_LIMIT:
			break
		var width := float(r.get("width_m", 0.0))
		if width < 7.0:
			continue
		var path := _project_ring(r["path"], proj)
		var off := width * 0.5 - 1.1  # just inside the kerb (parallel parking)
		for i in path.size() - 1:
			if coupe_transforms.size() + sedan_transforms.size() >= PARKED_CAR_LIMIT:
				break
			var a: Vector2 = path[i]
			var seg: Vector2 = path[i + 1] - a
			var seg_len := seg.length()
			if seg_len < 7.0:
				continue
			var dir := seg / seg_len
			var nrm := Vector2(-dir.y, dir.x)
			var yaw := atan2(dir.x, dir.y)  # align the car's length with the road
			var t := 5.0
			while (
				t < seg_len - 4.0
				and coupe_transforms.size() + sedan_transforms.size() < PARKED_CAR_LIMIT
			):
				if rng.randf() < 0.85:  # leave gaps so it's not bumper-to-bumper
					var p := a + dir * t + nrm * off
					var basis := Basis.from_euler(Vector3(0.0, yaw, 0.0))
					var transform := Transform3D(
						basis,
						Vector3(
							p.x, STREET_VISUAL_Y + VehicleVisualLibrary.MODEL_FLOOR_OFFSET_Y, p.y
						)
					)
					if rng.randi() % VehicleVisualLibrary.variant_count() == 0:
						coupe_transforms.append(transform)
					else:
						sedan_transforms.append(transform)
				t += PARKED_CAR_SPACING
	_add_parked_car_layer(coupe_mesh, coupe_transforms, "ParkedSportCoupes")
	_add_parked_car_layer(sedan_mesh, sedan_transforms, "ParkedClassicSedans")


func _add_parked_car_layer(mesh: Mesh, transforms: Array[Transform3D], node_name: String) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	add_child(mmi)


## Drop emissive lamp posts along the major roads (kerb side, ~42 m apart). They
## glow day and night and turn the dark city into a field of streetlights. Shared
## meshes/materials and a hard cap keep it cheap; the posts are visual only.
func _build_streetlights(roads: Array, proj: GeoProjection) -> void:
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.1, 0.1, 0.12)
	pole_mat.metallic = 0.6
	pole_mat.roughness = 0.5
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.92, 0.72)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.85, 0.55)
	lamp_mat.emission_energy_multiplier = 2.5
	var pole_mesh := BoxMesh.new()
	pole_mesh.size = Vector3(0.14, 5.0, 0.14)
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.5, 0.22, 0.32)

	var container := Node3D.new()
	container.name = "StreetLights"
	container.position.y = 0.15  # poles rise from the raised sidewalk
	add_child(container)
	# All lamp heads share lamp_mat, so one switch fades them all with day/night.
	var switch := StreetlightSwitch.new()
	switch.setup(lamp_mat, lamp_mat.emission_energy_multiplier)
	container.add_child(switch)

	var placed := 0
	var lights: Array[OmniLight3D] = []
	for r in roads:
		if placed >= 180:
			break
		if float(r.get("width_m", 0.0)) < 8.0:
			continue
		var path := _project_ring(r["path"], proj)
		for p in StreetLight.sample_along(path, 42.0, float(r["width_m"]) * 0.5 + 1.2):
			if placed >= 180:
				break
			var lamp := Node3D.new()
			lamp.position = Vector3(p.x, 0.0, p.y)
			var pole := MeshInstance3D.new()
			pole.mesh = pole_mesh
			pole.material_override = pole_mat
			pole.position = Vector3(0.0, 2.5, 0.0)
			lamp.add_child(pole)
			var head := MeshInstance3D.new()
			head.mesh = head_mesh
			head.material_override = lamp_mat
			head.position = Vector3(0.0, 5.0, 0.0)
			lamp.add_child(head)
			# A real warm pool under the first N heads turns the dark street into
			# lit asphalt at night; the rest stay emissive-only to keep the count
			# in budget. Shadowless and out of the volumetric pass for cheapness.
			if lights.size() < MAX_STREETLIGHT_LIGHTS:
				var glow := OmniLight3D.new()
				glow.omni_range = STREETLIGHT_LIGHT_RANGE_M
				glow.omni_attenuation = 1.5
				glow.light_color = Color(1.0, 0.85, 0.55)
				glow.light_energy = 0.0
				glow.light_volumetric_fog_energy = 0.0
				glow.shadow_enabled = false
				glow.visible = false
				glow.position = Vector3(0.0, 4.7, 0.0)
				lamp.add_child(glow)
				lights.append(glow)
			container.add_child(lamp)
			placed += 1
	switch.bind_lights(lights, STREETLIGHT_LIGHT_ENERGY)
	LodUtil.apply_range(container, 200.0)


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


## Weld the accumulated building geometry into the single "Buildings" mesh and
## its trimesh collider — the one deliberately chunky stage of the time-sliced
## build (collision cooking can't be split without splitting the mesh).
func _commit_buildings(
	verts: PackedVector3Array,
	norms: PackedVector3Array,
	idx: PackedInt32Array,
	colors: PackedColorArray
) -> void:
	if verts.is_empty():
		return
	var mesh := CityBuilder.arrays_to_mesh(
		{"vertices": verts, "normals": norms, "indices": idx, "colors": colors}
	)
	mesh.surface_set_material(0, _building_mat)
	var mi := MeshInstance3D.new()
	mi.name = "Buildings"
	mi.mesh = mesh
	add_child(mi)
	if build_collision:
		mi.create_trimesh_collision()


func _build_roads(roads: Array, proj: GeoProjection) -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var uvs := PackedVector2Array()

	for r in roads:
		var path := _project_ring(r["path"], proj)
		var geo := CityBuilder.road_ribbon(path, float(r["width_m"]), STREET_VISUAL_Y)
		if geo.is_empty():
			continue
		_append_geo(verts, norms, idx, geo)
		uvs.append_array(geo["uvs"])

	if verts.is_empty():
		return
	var mesh := CityBuilder.arrays_to_mesh(
		{"vertices": verts, "normals": norms, "indices": idx, "uvs": uvs}
	)
	mesh.surface_set_material(0, _road_mat)
	var mi := MeshInstance3D.new()
	mi.name = "Roads"
	mi.mesh = mesh
	add_child(mi)


## Raised concrete sidewalks flanking the wider roads — real curb geometry so the
## street reads as a kerbed avenue, not a flat painted floor. Merged into one
## MeshInstance3D (one draw call) like the roads. Narrow alleys/footways (<6 m)
## are skipped so they don't get double curbs.
func _build_sidewalks(roads: Array, proj: GeoProjection) -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var uvs := PackedVector2Array()

	for r in roads:
		var w := float(r.get("width_m", 0.0))
		if w < 6.0:
			continue
		var walk_width := 2.4 if w >= 10.0 else 1.8
		var path := _project_ring(r["path"], proj)
		var geo := CityBuilder.sidewalk_ribbon(path, w, walk_width, 0.15, SIDEWALK_VISUAL_Y)
		if geo.is_empty():
			continue
		_append_geo(verts, norms, idx, geo)
		uvs.append_array(geo["uvs"])

	if verts.is_empty():
		return
	var mesh := CityBuilder.arrays_to_mesh(
		{"vertices": verts, "normals": norms, "indices": idx, "uvs": uvs}
	)
	mesh.surface_set_material(0, _sidewalk_mat)
	var mi := MeshInstance3D.new()
	mi.name = "Sidewalks"
	mi.mesh = mesh
	add_child(mi)


## Spawn a flat ground tile covering the district's projected footprint so the
## player and vehicles have something to stand on, wherever the district sits in
## the shared world.
func _build_ground(data: Dictionary, proj: GeoProjection) -> void:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for collection in [data.get("buildings", []), data.get("roads", [])]:
		for item in collection:
			var pts: Array = item.get("footprint", item.get("path", []))
			for pair in pts:
				var p := proj.to_local(pair[0], pair[1])
				min_x = minf(min_x, p.x)
				max_x = maxf(max_x, p.x)
				min_z = minf(min_z, p.z)
				max_z = maxf(max_z, p.z)
	if min_x == INF:
		return

	var size_x := (max_x - min_x) + ground_margin * 2.0
	var size_z := (max_z - min_z) + ground_margin * 2.0
	var centre := Vector3((min_x + max_x) * 0.5, 0.0, (min_z + max_z) * 0.5)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.035, 0.045, 0.045)
	mat.roughness = 1.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = Vector3(size_x, 0.08, size_z)
	ground_mesh.material = mat

	var body := StaticBody3D.new()
	body.name = "Ground"
	body.position = centre
	var mi := MeshInstance3D.new()
	mi.mesh = ground_mesh
	# Sit the tile top just under the collider top (y=0) so the player rests on
	# the visible ground; the 0.08-thick slab is centred at -0.08 → top -0.04.
	mi.position.y = -0.08
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size_x, 1.0, size_z)
	col.shape = box
	col.position = Vector3(0, GROUND_SURFACE_Y - box.size.y * 0.5, 0)
	body.add_child(col)
	add_child(body)


## TimeOfDay (group "night_emissive") fades building windows in/out, 0..1.
func set_night_amount(amount: float) -> void:
	var shaded := _building_mat as ShaderMaterial
	if shaded != null:
		shaded.set_shader_parameter("night_mix", amount)


## Move the player + spawn marker onto a wide road segment near this district's
## centre so the first playable view opens down a street corridor, not at an
## arbitrary road endpoint or inside a building footprint.
func _place_actors_on_street(
	roads: Array, buildings: Array, proj: GeoProjection, centre: Vector3
) -> void:
	var best := centre
	var best_yaw := 0.0
	var best_score := INF
	var centre_xz := Vector2(centre.x, centre.z)
	var building_rings := _project_building_rings(buildings, proj)
	for r in roads:
		var width := float(r.get("width_m", 0.0))
		if width < 6.0:
			continue
		var path := _project_ring(r["path"], proj)
		for i in range(path.size() - 1):
			var a := path[i]
			var b := path[i + 1]
			var seg := b - a
			var seg_len := seg.length()
			if seg_len < 12.0:
				continue
			var mid := (a + b) * 0.5
			var dir := seg / seg_len
			var yaw := atan2(-dir.x, -dir.y)
			var forward := Vector2(-sin(yaw), -cos(yaw))
			var right := Vector2(cos(yaw), -sin(yaw))
			var camera_sample := mid - forward * 8.0 + right * 2.0
			var view_sample := mid + forward * 20.0
			var clearance := minf(
				_building_clearance(mid, building_rings),
				minf(
					_building_clearance(camera_sample, building_rings),
					_building_clearance(view_sample, building_rings)
				)
			)
			if clearance < 35.0:
				continue
			var score := (
				mid.distance_to(centre_xz)
				- minf(width, 16.0) * 12.0
				- minf(seg_len, 90.0)
				- minf(clearance, 80.0) * 8.0
			)
			if score < best_score:
				best_score = score
				best = Vector3(mid.x, 1.0, mid.y)
				best_yaw = yaw
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
			var camera_rig := (player as Node).get_node_or_null("CameraRig") as Node3D
			if camera_rig != null:
				camera_rig.rotation.y = best_yaw
	DistrictSpawnVista.build(self, best, best_yaw, STREET_VISUAL_Y)
	_place_starter_vehicles(best, best_yaw)


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


static func _project_building_rings(
	buildings: Array, proj: GeoProjection
) -> Array[PackedVector2Array]:
	var rings: Array[PackedVector2Array] = []
	for b in buildings:
		var raw: Array = b.get("footprint", [])
		if raw.size() < 3:
			continue
		var ring := _project_ring_static(raw, proj)
		if ring.size() >= 3:
			rings.append(ring)
	return rings


static func _building_clearance(point: Vector2, rings: Array[PackedVector2Array]) -> float:
	var nearest := INF
	for ring in rings:
		nearest = minf(nearest, _point_to_ring_distance(point, ring))
	return nearest


static func _point_to_ring_distance(point: Vector2, ring: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(point, ring):
		return 0.0
	var nearest := INF
	for i in ring.size():
		nearest = minf(
			nearest, _point_to_segment_distance(point, ring[i], ring[(i + 1) % ring.size()])
		)
	return nearest


static func _point_to_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq <= 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)


static func _project_ring_static(raw: Array, proj: GeoProjection) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for pair in raw:
		var p := proj.to_local(pair[0], pair[1])
		pts.append(Vector2(p.x, p.z))
	return pts


func _make_materials() -> void:
	# Procedural facade/asphalt shaders — no texture assets. Fall back to plain
	# greybox materials so the district still builds if a shader goes missing.
	# (Consolidation per LOOP_HANDOFF: facade.gdshader won over the parallel
	# building.gdshader/building_windows.gdshader; TimeOfDay drives its
	# night_mix uniform through set_night_amount.)
	_building_mat = _shader_or_fallback("res://shaders/facade.gdshader", Color(0.62, 0.63, 0.66))
	_road_mat = _shader_or_fallback("res://shaders/road.gdshader", Color(0.33, 0.32, 0.31))
	_sidewalk_mat = _shader_or_fallback("res://shaders/sidewalk.gdshader", Color(0.62, 0.60, 0.56))
	# Photoreal grain from the Codex-generated tileable albedos: asphalt on the
	# roads, troweled stucco breaking up the masonry facade fills.
	_set_detail_texture(_road_mat, "res://assets/textures/asphalt_albedo.png")
	_set_detail_texture(_building_mat, "res://assets/textures/stucco_albedo.png")

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
