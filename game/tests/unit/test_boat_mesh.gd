extends RefCounted
## Unit tests for BoatMesh procedural hull: correct bounds, a pointed bow, smooth
## normals, and a buildable surface.


func _aabb(geo: Dictionary) -> AABB:
	var verts: PackedVector3Array = geo["vertices"]
	var lo := verts[0]
	var hi := verts[0]
	for v in verts:
		lo = lo.min(v)
		hi = hi.max(v)
	return AABB(lo, hi - lo)


func test_hull_matches_requested_bounds() -> bool:
	var box := _aabb(BoatMesh.hull(3.4, 1.8, 0.8))
	return absf(box.size.z - 3.4) < 0.05 and box.size.x <= 1.8 + 0.01


func test_bow_is_pointed() -> bool:
	# Near the bow (min z) the hull must pinch — far narrower than amidships.
	var geo := BoatMesh.hull(3.4, 1.8, 0.8)
	var verts: PackedVector3Array = geo["vertices"]
	var bow_max_x := 0.0
	var mid_max_x := 0.0
	for v in verts:
		if v.z < -1.5:
			bow_max_x = maxf(bow_max_x, absf(v.x))
		elif absf(v.z) < 0.2:
			mid_max_x = maxf(mid_max_x, absf(v.x))
	return bow_max_x < 0.25 and mid_max_x > 0.6


func test_normals_are_unit_length() -> bool:
	var geo := BoatMesh.hull(3.4, 1.8, 0.8, 10, 12)
	for n in geo["normals"] as PackedVector3Array:
		if absf(n.length() - 1.0) > 0.001:
			return false
	return true


func test_indices_in_range() -> bool:
	var geo := BoatMesh.hull(3.4, 1.8, 0.8, 12, 12)
	var n: int = (geo["vertices"] as PackedVector3Array).size()
	for i in geo["indices"] as PackedInt32Array:
		if i < 0 or i >= n:
			return false
	return true


func test_to_mesh_builds_surface() -> bool:
	var mesh := BoatMesh.to_mesh(BoatMesh.hull())
	return mesh != null and mesh.get_surface_count() == 1


func test_to_mesh_empty_is_null() -> bool:
	return BoatMesh.to_mesh({}) == null
