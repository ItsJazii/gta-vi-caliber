class_name TestGroundMaterialBindings
extends GdUnitTestSuite

const GROUND_MATERIAL_BINDINGS := preload("res://scripts/world/ground_material_bindings.gd")


func test_sidewalk_bindings_lock_expected_texture_paths() -> void:
	assert_dict(GROUND_MATERIAL_BINDINGS.SIDEWALK_TEXTURE_PATHS).contains_keys(
		["detail_tex", "detail_roughness_tex"]
	)
	assert_str(GROUND_MATERIAL_BINDINGS.SIDEWALK_TEXTURE_PATHS["detail_tex"]).is_equal(
		"res://assets/materials/concrete_sidewalk_01/albedo.png"
	)
	assert_str(GROUND_MATERIAL_BINDINGS.SIDEWALK_TEXTURE_PATHS["detail_roughness_tex"]).is_equal(
		"res://assets/materials/concrete_sidewalk_01/roughness.png"
	)


func test_sand_bindings_lock_expected_texture_path() -> void:
	assert_str(GROUND_MATERIAL_BINDINGS.SAND_TEXTURE_PATHS["detail_tex"]).is_equal(
		"res://assets/textures/sand_albedo.png"
	)


func test_ground_uv_scales_stay_stable() -> void:
	assert_float(GROUND_MATERIAL_BINDINGS.SIDEWALK_FLOAT_PARAMS["detail_uv_scale"]).is_equal(0.32)
	assert_float(GROUND_MATERIAL_BINDINGS.SAND_FLOAT_PARAMS["detail_uv_scale"]).is_equal(0.045)
