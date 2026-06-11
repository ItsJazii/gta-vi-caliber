extends RefCounted
## Unit tests for PbrMaterial — the AI-texture-set → game-ready material pipeline.
## Channel-wiring logic is pure (channel_flags); from_set tolerates absent maps.


func test_channel_flags_all_present() -> bool:
	var f := PbrMaterial.channel_flags(
		PackedStringArray(["albedo", "normal", "roughness", "metallic", "ao", "emission"])
	)
	return (
		f["has_albedo"]
		and f["normal_enabled"]
		and f["roughness_textured"]
		and f["metallic_textured"]
		and f["ao_enabled"]
		and f["emission_enabled"]
	)


func test_channel_flags_partial_set() -> bool:
	# A common AI export: albedo + normal only. Nothing else should switch on.
	var f := PbrMaterial.channel_flags(PackedStringArray(["albedo", "normal"]))
	return (
		f["has_albedo"]
		and f["normal_enabled"]
		and not f["roughness_textured"]
		and not f["ao_enabled"]
		and not f["emission_enabled"]
	)


func test_channel_flags_empty() -> bool:
	var f := PbrMaterial.channel_flags(PackedStringArray())
	return not f["has_albedo"] and not f["normal_enabled"] and not f["ao_enabled"]


func test_from_set_missing_dir_is_valid_empty_material() -> bool:
	# No folder yet (textures not generated) must not crash — just a bare material.
	var mat := PbrMaterial.from_set("res://assets/materials/__does_not_exist__")
	return mat is StandardMaterial3D and mat.albedo_texture == null and not mat.normal_enabled


func test_from_set_triplanar_flag() -> bool:
	var mat := PbrMaterial.from_set("res://assets/materials/__none__", true, 4.0)
	return mat.uv1_triplanar and mat.uv1_world_triplanar and is_equal_approx(mat.uv1_scale.x, 4.0)
