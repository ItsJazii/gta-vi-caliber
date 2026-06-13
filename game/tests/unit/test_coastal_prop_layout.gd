extends RefCounted
## Guards the authored coastal prop layout used by the playable world.


func test_layout_has_four_of_each_prop() -> bool:
	var counts := {
		CoastalPropLayout.PALM_PLANTER: 0,
		CoastalPropLayout.PALM_TREE: 0,
		CoastalPropLayout.STREET_LAMP: 0,
	}
	for spec in CoastalPropLayout.placements():
		var kind: StringName = spec["kind"]
		counts[kind] += 1
	return (
		counts[CoastalPropLayout.PALM_PLANTER] == 4
		and counts[CoastalPropLayout.PALM_TREE] == 4
		and counts[CoastalPropLayout.STREET_LAMP] == 4
	)


func test_layout_names_are_unique() -> bool:
	var names := {}
	for spec in CoastalPropLayout.placements():
		names[spec["name"]] = true
	return names.size() == CoastalPropLayout.placements().size()


func test_layout_places_props_on_visible_ground() -> bool:
	for spec in CoastalPropLayout.placements():
		var position: Vector3 = spec["position"]
		if not is_equal_approx(position.y, CoastalPropLayout.GROUND_Y):
			return false
	return true


func test_layout_scales_small_source_models_to_world_size() -> bool:
	for spec in CoastalPropLayout.placements():
		if float(spec["scale"]) < 3.0:
			return false
	return true
