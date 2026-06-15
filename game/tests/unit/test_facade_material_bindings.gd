class_name TestFacadeMaterialBindings
extends GdUnitTestSuite

const FACADE_MATERIAL_BINDINGS := preload("res://scripts/world/facade_material_bindings.gd")


func test_texture_paths_cover_streamed_facade_sets() -> void:
	(
		assert_dict(FACADE_MATERIAL_BINDINGS.TEXTURE_PATHS)
		. contains_keys(
			[
				"masonry_albedo_tex",
				"masonry_roughness_tex",
				"concrete_albedo_tex",
				"concrete_roughness_tex",
				"tower_albedo_tex",
				"tower_roughness_tex",
				"tower_metallic_tex",
				"roof_albedo_tex",
				"roof_roughness_tex",
			]
		)
	)
	assert_str(FACADE_MATERIAL_BINDINGS.TEXTURE_PATHS["masonry_albedo_tex"]).is_equal(
		"res://assets/materials/facade_stucco_01/albedo.png"
	)
	assert_str(FACADE_MATERIAL_BINDINGS.TEXTURE_PATHS["tower_albedo_tex"]).is_equal(
		"res://assets/materials/facade_tower_01/albedo.png"
	)
	assert_str(FACADE_MATERIAL_BINDINGS.TEXTURE_PATHS["roof_albedo_tex"]).is_equal(
		"res://assets/materials/facade_brick_01/albedo.png"
	)


func test_float_params_lock_expected_uv_scales() -> void:
	assert_float(FACADE_MATERIAL_BINDINGS.FLOAT_PARAMS["masonry_uv_scale"]).is_equal(0.21)
	assert_float(FACADE_MATERIAL_BINDINGS.FLOAT_PARAMS["concrete_uv_scale"]).is_equal(0.18)
	assert_float(FACADE_MATERIAL_BINDINGS.FLOAT_PARAMS["tower_uv_scale"]).is_equal(0.24)
	assert_float(FACADE_MATERIAL_BINDINGS.FLOAT_PARAMS["roof_uv_scale"]).is_equal(0.16)
