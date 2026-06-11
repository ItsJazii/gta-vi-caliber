extends RefCounted
## Unit tests for HumanoidMesh procedural body geometry. The body is built from
## pure lofted surfaces, so vertex/index counts, watertight cap topology, smooth
## outward normals, and per-part dimensions all have to be exactly right.

# A straight 3-ring cylinder, radius 0.5, height 2, 8 sides — easy to count.
var _cyl_rings := [Vector3(1, 0.5, 0.5), Vector3(0, 0.5, 0.5), Vector3(-1, 0.5, 0.5)]


func _aabb(geo: Dictionary) -> AABB:
	var verts: PackedVector3Array = geo["vertices"]
	var lo := verts[0]
	var hi := verts[0]
	for v in verts:
		lo = lo.min(v)
		hi = hi.max(v)
	return AABB(lo, hi - lo)


func test_lofted_rejects_too_few_rings() -> bool:
	return HumanoidMesh.lofted([Vector3(0, 1, 1)], 8).is_empty()


func test_lofted_rejects_too_few_segments() -> bool:
	return HumanoidMesh.lofted(_cyl_rings, 2).is_empty()


func test_cylinder_vertex_count() -> bool:
	# 3 rings × 8 + 2 cap centres = 26.
	var geo := HumanoidMesh.lofted(_cyl_rings, 8)
	return (geo["vertices"] as PackedVector3Array).size() == 26


func test_cylinder_index_count() -> bool:
	# sides: 2 strips × 8 segs × 2 tris × 3 = 96; caps: 2 × 8 tris × 3 = 48.
	var geo := HumanoidMesh.lofted(_cyl_rings, 8)
	return (geo["indices"] as PackedInt32Array).size() == 144


func test_indices_in_range() -> bool:
	var geo := HumanoidMesh.lofted(_cyl_rings, 8)
	var n: int = (geo["vertices"] as PackedVector3Array).size()
	for i in geo["indices"] as PackedInt32Array:
		if i < 0 or i >= n:
			return false
	return true


func test_normals_are_unit_length() -> bool:
	var geo := HumanoidMesh.lofted(_cyl_rings, 8)
	for nrm in geo["normals"] as PackedVector3Array:
		if absf(nrm.length() - 1.0) > 0.001:
			return false
	return true


func test_middle_ring_normals_point_outward() -> bool:
	# The middle ring of a straight cylinder must shade purely radially outward —
	# this is the guard that the side winding produces outward (not inward) faces.
	var geo := HumanoidMesh.lofted(_cyl_rings, 8)
	var verts: PackedVector3Array = geo["vertices"]
	var normals: PackedVector3Array = geo["normals"]
	for k in range(8, 16):  # ring index 1 occupies vertices 8..15
		var radial := Vector3(verts[k].x, 0.0, verts[k].z).normalized()
		if normals[k].dot(radial) < 0.9:
			return false
	return true


func test_limb_height_matches_length() -> bool:
	var box := _aabb(HumanoidMesh.limb(0.6, 0.06, 0.07, 0.05))
	return absf(box.size.y - 0.6) < 0.01


func test_torso_height_matches() -> bool:
	var box := _aabb(HumanoidMesh.torso(0.6))
	return absf(box.size.y - 0.6) < 0.01


func test_head_is_taller_than_wide() -> bool:
	var box := _aabb(HumanoidMesh.head(0.28, 0.13, 0.13))
	return absf(box.size.y - 0.28) < 0.01 and box.size.x < box.size.y


func test_foot_is_longest_along_z() -> bool:
	# The shoe is lofted along +Z, so its longest extent must be depth, not width.
	var box := _aabb(HumanoidMesh.foot(0.3, 0.09, 0.06))
	return box.size.z > box.size.x and box.size.z > box.size.y


func test_neck_height_matches() -> bool:
	var box := _aabb(HumanoidMesh.neck(0.16, 0.052))
	return absf(box.size.y - 0.16) < 0.01


func test_all_parts_build_nonempty() -> bool:
	var parts := [
		HumanoidMesh.torso(),
		HumanoidMesh.pelvis(),
		HumanoidMesh.neck(),
		HumanoidMesh.head(),
		HumanoidMesh.hair(),
		HumanoidMesh.arm(),
		HumanoidMesh.leg(),
		HumanoidMesh.hand(),
		HumanoidMesh.foot(),
	]
	for geo in parts:
		if geo.is_empty() or (geo["vertices"] as PackedVector3Array).is_empty():
			return false
	return true


func test_to_mesh_builds_one_surface() -> bool:
	var mesh := HumanoidMesh.to_mesh(HumanoidMesh.arm())
	return mesh != null and mesh.get_surface_count() == 1


func test_to_mesh_empty_is_null() -> bool:
	return HumanoidMesh.to_mesh({}) == null
