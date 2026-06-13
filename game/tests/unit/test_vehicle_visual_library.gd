extends RefCounted
## Coverage for selecting the new production vehicle models and their ambient
## traffic LODs without depending on a running scene tree.


func test_library_contains_both_vehicle_models() -> bool:
	return VehicleVisualLibrary.variant_count() == 2


func test_variant_selection_wraps() -> bool:
	return (
		VehicleVisualLibrary.normalize_variant(2) == VehicleVisualLibrary.Variant.SPORT_COUPE
		and VehicleVisualLibrary.normalize_variant(-1) == VehicleVisualLibrary.Variant.CLASSIC_SEDAN
	)


func test_playable_variants_have_meshes() -> bool:
	for variant in VehicleVisualLibrary.variant_count():
		var root := VehicleVisualLibrary.instantiate_playable(variant)
		var visual := VehicleVisualLibrary.first_mesh_instance(root)
		var valid := visual != null and visual.mesh != null
		root.free()
		if not valid:
			return false
	return true


func test_traffic_variants_keep_original_materials() -> bool:
	for variant in VehicleVisualLibrary.variant_count():
		var visual := VehicleVisualLibrary.instantiate_traffic(variant)
		var mesh := visual.mesh
		var valid := (
			mesh != null and mesh.get_surface_count() > 0 and mesh.surface_get_material(0) != null
		)
		visual.free()
		if not valid:
			return false
	return true


func test_traffic_variants_are_lifted_to_their_tyre_plane() -> bool:
	for variant in VehicleVisualLibrary.variant_count():
		var visual := VehicleVisualLibrary.instantiate_traffic(variant)
		var valid := is_equal_approx(visual.position.y, VehicleVisualLibrary.MODEL_FLOOR_OFFSET_Y)
		visual.free()
		if not valid:
			return false
	return true
