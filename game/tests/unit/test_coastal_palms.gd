extends RefCounted
## Functional guards for CoastalPalms — the shoreline palm fringe. FloridaMapModel
## is pure, so populate() runs headless. Guards the fringe is populated, capped,
## region-clipped, and renders as the two named MultiMesh layers (trunks +
## crowns) with matching instance counts.


func test_populates_within_cap() -> bool:
	var palms := CoastalPalms.new()
	var n := palms.populate()
	palms.free()
	return n > 0 and n <= 600


func test_layers_match_count() -> bool:
	var palms := CoastalPalms.new()
	var n := palms.populate()
	var by_name := {}
	for child in palms.get_children():
		if child is MultiMeshInstance3D:
			by_name[child.name] = child.multimesh.instance_count
	palms.free()
	return by_name.get("CoastalPalmTrunks", -1) == n and by_name.get("CoastalPalmCrowns", -1) == n


func test_cap_is_respected() -> bool:
	var palms := CoastalPalms.new()
	palms.max_palms = 40
	palms.spacing = 8.0
	var n := palms.populate()
	palms.free()
	return n == 40


func test_populate_is_idempotent() -> bool:
	var palms := CoastalPalms.new()
	var first := palms.populate()
	var second := palms.populate()
	var layers := 0
	for child in palms.get_children():
		if child is MultiMeshInstance3D:
			layers += 1
	palms.free()
	# Second call must no-op: same count, still only two layers (no duplicates).
	return first == second and layers == 2
