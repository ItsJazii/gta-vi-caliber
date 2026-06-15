class_name DistrictTileBuilder
extends RefCounted
## Pure, thread-friendly preparation for streamed OSM districts.
##
## File parsing, projection, tile partitioning, and mesh-array generation happen
## away from the SceneTree. DistrictLoader consumes one prepared 128 m tile at a
## time on the main thread.

const COLLISION_TRIANGLES_PER_BATCH: int = 16
const STREET_VISUAL_Y: float = 0.32
const SIDEWALK_VISUAL_Y: float = 0.28


static func build_from_path(path: String, tile_size: float) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is not Dictionary:
		return {}
	return build(parsed as Dictionary, tile_size)


static func build(data: Dictionary, tile_size: float) -> Dictionary:
	if data.is_empty() or not data.has("origin"):
		return {}
	var origin: Dictionary = data["origin"]
	var projection := GeoProjection.new(float(origin["lat"]), float(origin["lon"]))
	var chunks: Dictionary = {}
	var buildings: Array = data.get("buildings", [])
	var roads: Array = data.get("roads", [])
	var centroid: Dictionary = data.get("centroid", origin)
	var centre := projection.to_local(float(centroid["lat"]), float(centroid["lon"]))

	for building: Dictionary in buildings:
		_append_building(chunks, building, projection, tile_size)
	for road: Dictionary in roads:
		_append_road(chunks, road, projection, tile_size)
	_append_facades(chunks, buildings, projection, tile_size, Vector2(centre.x, centre.z))

	var ordered_chunks: Array[Dictionary] = []
	for coord: Vector2i in chunks:
		var chunk: Dictionary = chunks[coord]
		var navigation_geo: Dictionary = (
			chunk["sidewalks_geo"]
			if not (chunk["sidewalks_geo"]["vertices"] as PackedVector3Array).is_empty()
			else chunk["roads_geo"]
		)
		chunk["coord"] = coord
		chunk["center"] = TileMath.tile_center(coord, tile_size)
		chunk["collision_face_batches"] = _triangle_face_batches(chunk["buildings_geo"])
		chunk["navigation_vertices"] = navigation_geo["vertices"]
		chunk["navigation_polygons"] = _triangle_polygons(navigation_geo["indices"])
		var rooftop_transforms := _rooftop_transforms(chunk["buildings"], projection, 12)
		for key: String in rooftop_transforms:
			chunk[key] = rooftop_transforms[key]
		ordered_chunks.append(chunk)
	ordered_chunks.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var ac: Vector2i = a["coord"]
			var bc: Vector2i = b["coord"]
			return ac.y < bc.y or (ac.y == bc.y and ac.x < bc.x)
	)

	var spawn := _find_spawn(roads, buildings, projection, centre)
	return {
		"name": str(data.get("name", "district")),
		"origin": origin,
		"chunks": ordered_chunks,
		"building_count": buildings.size(),
		"road_count": roads.size(),
		"spawn_position": spawn["position"],
		"spawn_yaw": spawn["yaw"],
		"spawn_width": spawn["width"],
	}


static func _append_building(
	chunks: Dictionary, building: Dictionary, projection: GeoProjection, tile_size: float
) -> void:
	var ring := _project_ring(building.get("footprint", []), projection)
	if ring.size() < 3:
		return
	var coord := TileMath.tile_coord(_centre_3d(ring), tile_size)
	var chunk := _chunk(chunks, coord)
	(chunk["buildings"] as Array).append(building)

	var height := float(building.get("height_m", 0.0))
	var detailed := CityBuilder.extrude_prism(ring, 0.0, height)
	if detailed.is_empty():
		return
	var building_id := int(building.get("id", 0))
	var tint := CityBuilder.building_color(building_id)
	tint.a = CityBuilder.building_glass_seed(building_id, height)
	_append_geo(chunk["buildings_geo"], detailed, tint)

	var hlod_ring := _bounding_ring(ring)
	var hlod := CityBuilder.extrude_prism(hlod_ring, 0.0, height)
	_append_geo(chunk["hlod_geo"], hlod, tint)
	chunks[coord] = chunk


static func _append_road(
	chunks: Dictionary, road: Dictionary, projection: GeoProjection, tile_size: float
) -> void:
	var path := _project_ring(road.get("path", []), projection)
	if path.size() < 2:
		return
	var coord := TileMath.tile_coord(_centre_3d(path), tile_size)
	var chunk := _chunk(chunks, coord)
	(chunk["roads"] as Array).append(road)
	var width := float(road.get("width_m", 0.0))
	_append_geo(chunk["roads_geo"], CityBuilder.road_ribbon(path, width, STREET_VISUAL_Y))
	if width >= 6.0:
		var walk_width := 2.4 if width >= 10.0 else 1.8
		_append_geo(
			chunk["sidewalks_geo"],
			CityBuilder.sidewalk_ribbon(path, width, walk_width, 0.15, SIDEWALK_VISUAL_Y)
		)
	chunks[coord] = chunk


static func _append_facades(
	chunks: Dictionary,
	buildings: Array,
	projection: GeoProjection,
	tile_size: float,
	focus: Vector2
) -> void:
	var candidates: Array[Dictionary] = []
	for building: Dictionary in buildings:
		var height := float(building.get("height_m", 0.0))
		if height < 8.0:
			continue
		var ring := _project_ring(building.get("footprint", []), projection)
		if ring.size() < 3:
			continue
		var centre := _centre_3d(ring)
		(
			candidates
			. append(
				{
					"building": building,
					"height": height,
					"ring": ring,
					"distance_squared": focus.distance_squared_to(Vector2(centre.x, centre.z)),
				}
			)
		)
	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["distance_squared"]) < float(b["distance_squared"])
	)

	var dark: Array[Transform3D] = []
	var lit: Array[Transform3D] = []
	for candidate: Dictionary in candidates:
		if (
			dark.size() >= DistrictFacadePanels.DARK_CAP
			and lit.size() >= DistrictFacadePanels.LIT_CAP
		):
			break
		var building: Dictionary = candidate["building"]
		DistrictFacadePanels.collect_transforms(
			candidate["ring"], float(candidate["height"]), int(building.get("id", 0)), dark, lit
		)
	for transform: Transform3D in dark:
		_append_facade_transform(chunks, transform, tile_size, "facade_dark")
	for transform: Transform3D in lit:
		_append_facade_transform(chunks, transform, tile_size, "facade_lit")


static func _append_facade_transform(
	chunks: Dictionary, transform: Transform3D, tile_size: float, key: String
) -> void:
	var coord := TileMath.tile_coord(transform.origin, tile_size)
	var chunk := _chunk(chunks, coord)
	(chunk[key] as Array[Transform3D]).append(transform)
	chunks[coord] = chunk


static func _chunk(chunks: Dictionary, coord: Vector2i) -> Dictionary:
	if chunks.has(coord):
		return chunks[coord]
	return {
		"buildings": [],
		"roads": [],
		"buildings_geo": _empty_geo(true),
		"hlod_geo": _empty_geo(true),
		"roads_geo": _empty_geo(false, true),
		"sidewalks_geo": _empty_geo(false, true),
		"collision_face_batches": [] as Array[PackedVector3Array],
		"navigation_vertices": PackedVector3Array(),
		"navigation_polygons": [] as Array[PackedInt32Array],
		"facade_dark": [] as Array[Transform3D],
		"facade_lit": [] as Array[Transform3D],
		"rooftop_ac": [] as Array[Transform3D],
		"rooftop_tanks": [] as Array[Transform3D],
		"rooftop_houses": [] as Array[Transform3D],
		"rooftop_masts": [] as Array[Transform3D],
		"rooftop_beacons": [] as Array[Transform3D],
	}


static func _empty_geo(with_colors: bool = false, with_uvs: bool = false) -> Dictionary:
	var geo := {
		"vertices": PackedVector3Array(),
		"normals": PackedVector3Array(),
		"indices": PackedInt32Array(),
	}
	if with_colors:
		geo["colors"] = PackedColorArray()
	if with_uvs:
		geo["uvs"] = PackedVector2Array()
	return geo


static func _triangle_polygons(indices: PackedInt32Array) -> Array[PackedInt32Array]:
	var polygons: Array[PackedInt32Array] = []
	for index in range(0, indices.size() - 2, 3):
		polygons.append(PackedInt32Array([indices[index], indices[index + 1], indices[index + 2]]))
	return polygons


static func _triangle_face_batches(geo: Dictionary) -> Array[PackedVector3Array]:
	var batches: Array[PackedVector3Array] = []
	var vertices: PackedVector3Array = geo["vertices"]
	var indices: PackedInt32Array = geo["indices"]
	var batch_size := COLLISION_TRIANGLES_PER_BATCH * 3
	for start in range(0, indices.size(), batch_size):
		var faces := PackedVector3Array()
		for index in range(start, mini(start + batch_size, indices.size())):
			faces.append(vertices[indices[index]])
		batches.append(faces)
	return batches


static func _rooftop_transforms(
	buildings: Array, projection: GeoProjection, limit: int
) -> Dictionary:
	var ac: Array[Transform3D] = []
	var tanks: Array[Transform3D] = []
	var houses: Array[Transform3D] = []
	var masts: Array[Transform3D] = []
	var beacons: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var placed := 0
	for building: Dictionary in buildings:
		if placed >= limit:
			break
		var height := float(building.get("height_m", 0.0))
		if height < 6.0:
			continue
		var ring := _project_ring(building.get("footprint", []), projection)
		if ring.size() < 3:
			continue
		var minimum := Vector2(INF, INF)
		var maximum := Vector2(-INF, -INF)
		var centre := Vector2.ZERO
		for point: Vector2 in ring:
			centre += point
			minimum = minimum.min(point)
			maximum = maximum.max(point)
		centre /= float(ring.size())
		var extent := maximum - minimum
		var roof := Vector3(centre.x, height, centre.y)
		if height >= 22.0 and extent.x > 6.0 and extent.y > 6.0:
			var width := clampf(extent.x * rng.randf_range(0.3, 0.5), 3.0, 16.0)
			var depth := clampf(extent.y * rng.randf_range(0.3, 0.5), 3.0, 16.0)
			var prop_height := rng.randf_range(3.0, 6.0)
			var offset := Vector3(rng.randf_range(-1.5, 1.5), 0.0, rng.randf_range(-1.5, 1.5))
			houses.append(
				Transform3D(
					Basis.from_scale(Vector3(width, prop_height, depth)),
					roof + offset + Vector3(0.0, prop_height * 0.5, 0.0)
				)
			)
		if height >= 50.0:
			var mast_height := rng.randf_range(8.0, 18.0)
			masts.append(
				Transform3D(
					Basis.from_scale(Vector3(1.0, mast_height, 1.0)),
					roof + Vector3(0.0, mast_height * 0.5, 0.0)
				)
			)
			beacons.append(Transform3D(Basis.IDENTITY, roof + Vector3(0.0, mast_height, 0.0)))
		elif height >= 12.0:
			tanks.append(
				Transform3D(
					Basis.IDENTITY,
					roof + Vector3(rng.randf_range(-2.5, 2.5), 1.1, rng.randf_range(-2.5, 2.5))
				)
			)
		elif extent.x > 4.0 and extent.y > 4.0:
			var width := clampf(minf(extent.x, extent.y) * rng.randf_range(0.25, 0.4), 2.0, 5.0)
			var prop_height := rng.randf_range(1.8, 2.8)
			houses.append(
				Transform3D(
					Basis.from_scale(Vector3(width, prop_height, width)),
					(
						roof
						+ Vector3(
							rng.randf_range(-1.0, 1.0),
							prop_height * 0.5,
							rng.randf_range(-1.0, 1.0)
						)
					)
				)
			)
		ac.append(
			Transform3D(
				Basis(Vector3.UP, rng.randf() * TAU),
				roof + Vector3(rng.randf_range(-3.0, 3.0), 0.6, rng.randf_range(-3.0, 3.0))
			)
		)
		placed += 1
	return {
		"rooftop_ac": ac,
		"rooftop_tanks": tanks,
		"rooftop_houses": houses,
		"rooftop_masts": masts,
		"rooftop_beacons": beacons,
	}


static func _append_geo(target: Dictionary, source: Dictionary, color: Color = Color.WHITE) -> void:
	if source.is_empty():
		return
	var vertices: PackedVector3Array = target["vertices"]
	var normals: PackedVector3Array = target["normals"]
	var indices: PackedInt32Array = target["indices"]
	var offset := vertices.size()
	var source_vertices: PackedVector3Array = source["vertices"]
	vertices.append_array(source_vertices)
	normals.append_array(source["normals"])
	for index: int in source["indices"]:
		indices.append(offset + index)
	target["vertices"] = vertices
	target["normals"] = normals
	target["indices"] = indices
	if target.has("uvs") and source.has("uvs"):
		var uvs: PackedVector2Array = target["uvs"]
		uvs.append_array(source["uvs"])
		target["uvs"] = uvs
	if target.has("colors"):
		var colors: PackedColorArray = target["colors"]
		for _index in source_vertices.size():
			colors.append(color)
		target["colors"] = colors


static func _project_ring(raw: Array, projection: GeoProjection) -> PackedVector2Array:
	var points := PackedVector2Array()
	for pair: Array in raw:
		points.append(projection.to_local_2d(float(pair[0]), float(pair[1])))
	return points


static func _centre_3d(points: PackedVector2Array) -> Vector3:
	var centre := Vector2.ZERO
	for point: Vector2 in points:
		centre += point
	centre /= maxf(float(points.size()), 1.0)
	return Vector3(centre.x, 0.0, centre.y)


static func _bounding_ring(ring: PackedVector2Array) -> PackedVector2Array:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for point: Vector2 in ring:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	if minimum.x == INF:
		return PackedVector2Array()
	return PackedVector2Array(
		[
			minimum,
			Vector2(maximum.x, minimum.y),
			maximum,
			Vector2(minimum.x, maximum.y),
		]
	)


static func _find_spawn(
	roads: Array, buildings: Array, projection: GeoProjection, centre: Vector3
) -> Dictionary:
	var best := centre
	var best_yaw := 0.0
	var best_width := VehicleSpawnLayout.DEFAULT_ROAD_WIDTH
	var best_score := INF
	var centre_xz := Vector2(centre.x, centre.z)
	var building_rings: Array[PackedVector2Array] = []
	for building: Dictionary in buildings:
		var ring := _project_ring(building.get("footprint", []), projection)
		if ring.size() >= 3:
			building_rings.append(ring)
	for road: Dictionary in roads:
		var width := float(road.get("width_m", 0.0))
		if width < 6.0:
			continue
		var path := _project_ring(road.get("path", []), projection)
		for index in range(path.size() - 1):
			var a := path[index]
			var b := path[index + 1]
			var segment := b - a
			var segment_length := segment.length()
			if segment_length < 12.0:
				continue
			var midpoint := (a + b) * 0.5
			var direction := segment / segment_length
			var yaw := atan2(-direction.x, -direction.y)
			var forward := Vector2(-sin(yaw), -cos(yaw))
			var right := Vector2(cos(yaw), -sin(yaw))
			var camera_sample := midpoint - forward * 8.0 + right * 2.0
			var view_sample := midpoint + forward * 20.0
			var clearance := minf(
				_building_clearance(midpoint, building_rings),
				minf(
					_building_clearance(camera_sample, building_rings),
					_building_clearance(view_sample, building_rings)
				)
			)
			if clearance < 35.0:
				continue
			var score := (
				midpoint.distance_to(centre_xz)
				- minf(width, 16.0) * 12.0
				- minf(segment_length, 90.0)
				- minf(clearance, 80.0) * 8.0
			)
			if score < best_score:
				best_score = score
				best = Vector3(midpoint.x, 1.0, midpoint.y)
				best_yaw = yaw
				best_width = width
	best.y = 1.0
	return {"position": best, "yaw": best_yaw, "width": best_width}


static func _building_clearance(point: Vector2, building_rings: Array[PackedVector2Array]) -> float:
	var nearest := INF
	for ring: PackedVector2Array in building_rings:
		nearest = minf(nearest, _point_to_ring_distance(point, ring))
	return nearest


static func _point_to_ring_distance(point: Vector2, ring: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(point, ring):
		return 0.0
	var nearest := INF
	for index in ring.size():
		nearest = minf(
			nearest, _point_to_segment_distance(point, ring[index], ring[(index + 1) % ring.size()])
		)
	return nearest


static func _point_to_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var segment := b - a
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(a + segment * t)
