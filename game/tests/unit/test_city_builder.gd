extends RefCounted
## Unit tests for CityBuilder geometry. Buildings and roads are generated from
## hundreds of real footprints, so the prism/ribbon math has to be exactly right.

# PackedVector2Array(...) is not a constant expression in GDScript, so this
# shared fixture is a runtime member rather than a const.
var _square := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])


func test_clean_ring_drops_closing_duplicate() -> bool:
	var closed := PackedVector2Array(
		[Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10), Vector2(0, 0)]
	)
	return CityBuilder.clean_ring(closed).size() == 4


func test_prism_vertex_and_index_counts() -> bool:
	# 4 walls × 4 verts + 4 roof verts = 20 verts.
	# 4 walls × 6 + roof (4-2)×3 = 24 + 6 = 30 indices.
	var geo := CityBuilder.extrude_prism(_square, 0.0, 25.0)
	var verts: PackedVector3Array = geo["vertices"]
	var idx: PackedInt32Array = geo["indices"]
	return verts.size() == 20 and idx.size() == 30


func test_prism_reaches_requested_height() -> bool:
	var geo := CityBuilder.extrude_prism(_square, 5.0, 100.0)
	var max_y := -INF
	var min_y := INF
	for v in geo["vertices"] as PackedVector3Array:
		max_y = maxf(max_y, v.y)
		min_y = minf(min_y, v.y)
	return absf(max_y - 105.0) < 0.001 and absf(min_y - 5.0) < 0.001


func test_prism_normals_are_unit_length() -> bool:
	var geo := CityBuilder.extrude_prism(_square, 0.0, 10.0)
	for nrm in geo["normals"] as PackedVector3Array:
		if absf(nrm.length() - 1.0) > 0.001:
			return false
	return true


func test_degenerate_footprint_returns_empty() -> bool:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(1, 1)])
	return CityBuilder.extrude_prism(line, 0.0, 10.0).is_empty()


func test_signed_area_sign_follows_winding() -> bool:
	var ccw := CityBuilder.signed_area(_square)
	var cw := _square.duplicate()
	cw.reverse()
	return ccw > 0.0 and CityBuilder.signed_area(cw) < 0.0


func test_winding_is_normalised_before_extrude() -> bool:
	# A clockwise footprint must produce the same mesh size as its CCW twin.
	var cw := _square.duplicate()
	cw.reverse()
	var a := CityBuilder.extrude_prism(_square, 0.0, 10.0)
	var b := CityBuilder.extrude_prism(cw, 0.0, 10.0)
	return (
		(a["vertices"] as PackedVector3Array).size() == (b["vertices"] as PackedVector3Array).size()
	)


func test_road_ribbon_quad_per_segment() -> bool:
	# 3 points → 2 segments → 8 verts, 12 indices.
	var path := PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(40, 0)])
	var geo := CityBuilder.road_ribbon(path, 8.0, 0.05)
	return (
		(geo["vertices"] as PackedVector3Array).size() == 8
		and (geo["indices"] as PackedInt32Array).size() == 12
	)


func test_road_ribbon_width_is_correct() -> bool:
	var path := PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])
	var geo := CityBuilder.road_ribbon(path, 6.0, 0.0)
	var verts: PackedVector3Array = geo["vertices"]
	# First two verts straddle the start point across the 6 m width.
	return absf(verts[0].distance_to(verts[1]) - 6.0) < 0.001


func test_arrays_to_mesh_builds_surface() -> bool:
	var geo := CityBuilder.extrude_prism(_square, 0.0, 10.0)
	var mesh := CityBuilder.arrays_to_mesh(geo)
	return mesh != null and mesh.get_surface_count() == 1


func test_arrays_to_mesh_empty_is_null() -> bool:
	return CityBuilder.arrays_to_mesh({}) == null


func test_road_ribbon_faces_up_when_culled() -> bool:
	# Godot front faces wind clockwise seen from the front (PlaneMesh does the
	# same). A wrong winding back-face-culls every road — they render invisible.
	var geo := CityBuilder.road_ribbon(
		PackedVector2Array([Vector2(0, 0), Vector2(10, 0)]), 6.0, 0.0
	)
	var v: PackedVector3Array = geo["vertices"]
	var idx: PackedInt32Array = geo["indices"]
	var t := 0
	while t < idx.size():
		var n := (v[idx[t + 1]] - v[idx[t]]).cross(v[idx[t + 2]] - v[idx[t]])
		if n.y >= 0.0:
			return false
		t += 3
	return true


func test_road_ribbon_uvs_track_width_and_length() -> bool:
	# UV.x spans the ribbon width 0..1; UV.y accumulates metres along the path.
	var path := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 30)])
	var geo := CityBuilder.road_ribbon(path, 6.0, 0.05)
	var uvs: PackedVector2Array = geo["uvs"]
	if uvs.size() != (geo["vertices"] as PackedVector3Array).size():
		return false
	return (
		uvs[0].is_equal_approx(Vector2(0.0, 0.0))
		and uvs[2].is_equal_approx(Vector2(1.0, 10.0))
		and uvs[7].is_equal_approx(Vector2(0.0, 40.0))
	)


func test_arrays_to_mesh_packs_uvs_and_colors() -> bool:
	var geo := CityBuilder.road_ribbon(PackedVector2Array([Vector2(0, 0), Vector2(8, 0)]), 4.0, 0.0)
	var colors := PackedColorArray()
	for _i in (geo["vertices"] as PackedVector3Array).size():
		colors.append(Color.WHITE)
	geo["colors"] = colors
	var mesh := CityBuilder.arrays_to_mesh(geo)
	var arrays := mesh.surface_get_arrays(0)
	return (
		(arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() == 4
		and (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size() == 4
	)


func test_building_color_is_deterministic() -> bool:
	var first := CityBuilder.building_color(23973401)
	var second := CityBuilder.building_color(23973401)
	return first == second


func test_building_color_stays_sun_bleached() -> bool:
	# Every id must land in the light worn-stucco range — never dark or garish.
	for i in 64:
		var c := CityBuilder.building_color(i * 7919 + 13)
		if c.r < 0.3 or c.g < 0.3 or c.b < 0.3:
			return false
		if c.r > 1.0 or c.g > 1.0 or c.b > 1.0:
			return false
		if c.get_luminance() < 0.5:
			return false
	return true


func test_building_color_varies_across_ids() -> bool:
	var seen := {}
	for i in 32:
		seen[CityBuilder.building_color(i * 104729 + 7)] = true
	return seen.size() >= 4
