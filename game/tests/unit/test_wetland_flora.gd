extends RefCounted
## Unit tests for WetlandFlora — the clustered wetland-vegetation builder.
## Guards that seed points expand into dense clusters (not 1:1 lollipops) and
## that the three named layers are attached with matching instance counts.


func _mat() -> StandardMaterial3D:
	return StandardMaterial3D.new()


func test_clusters_multiply_seed_points() -> bool:
	var parent := Node3D.new()
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(50, 50), Vector2(-30, 20)])
	var counts := WetlandFlora.build(parent, pts, 0.0, _mat(), _mat(), _mat(), 7)
	# Every seed yields >= TREES_PER_CLUSTER_MIN trees, so trees >> seed count.
	var ok: bool = counts["trees"] >= pts.size() * WetlandFlora.TREES_PER_CLUSTER_MIN
	# Two stacked crowns per tree, and a denser shrub understory.
	ok = ok and counts["crowns"] == counts["trees"] * 2
	ok = ok and counts["shrubs"] >= pts.size() * WetlandFlora.SHRUBS_PER_CLUSTER_MIN
	parent.free()
	return ok


func test_attaches_three_named_layers_with_matching_counts() -> bool:
	var parent := Node3D.new()
	var counts := WetlandFlora.build(
		parent, PackedVector2Array([Vector2(0, 0)]), 0.0, _mat(), _mat(), _mat(), 3
	)
	var by_name := {}
	for child in parent.get_children():
		if child is MultiMeshInstance3D:
			by_name[child.name] = child.multimesh.instance_count
	var ok: bool = by_name.size() == 3
	ok = ok and by_name.get("WetlandCypressTrunks", -1) == counts["trees"]
	ok = ok and by_name.get("WetlandCypressCrowns", -1) == counts["crowns"]
	ok = ok and by_name.get("WetlandShrubs", -1) == counts["shrubs"]
	parent.free()
	return ok


func test_seed_is_deterministic() -> bool:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(10, -5)])
	var a := Node3D.new()
	var b := Node3D.new()
	var ca := WetlandFlora.build(a, pts, 0.0, _mat(), _mat(), _mat(), 42)
	var cb := WetlandFlora.build(b, pts, 0.0, _mat(), _mat(), _mat(), 42)
	a.free()
	b.free()
	return ca["trees"] == cb["trees"] and ca["shrubs"] == cb["shrubs"]


func test_crowns_carry_per_instance_colors() -> bool:
	# Tone variation rides on MultiMesh instance colours, so the crown layer must
	# have use_colors enabled (the shrub layer too); trunks stay uncoloured.
	var parent := Node3D.new()
	WetlandFlora.build(parent, PackedVector2Array([Vector2(0, 0)]), 0.0, _mat(), _mat(), _mat(), 1)
	var crowns_coloured := false
	var trunks_plain := false
	for child in parent.get_children():
		if child.name == "WetlandCypressCrowns":
			crowns_coloured = child.multimesh.use_colors
		elif child.name == "WetlandCypressTrunks":
			trunks_plain = not child.multimesh.use_colors
	parent.free()
	return crowns_coloured and trunks_plain
