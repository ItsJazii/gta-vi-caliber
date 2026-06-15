class_name FacadeMaterialBindings
extends RefCounted
## Shared streamed-city facade material bindings. Kept in one place so the live
## district loader and tests agree on which Miami facade sets should be wired
## into `facade.gdshader`.

const TEXTURE_PATHS := {
	"masonry_albedo_tex": "res://assets/materials/facade_stucco_01/albedo.png",
	"masonry_roughness_tex": "res://assets/materials/facade_stucco_01/roughness.png",
	"concrete_albedo_tex": "res://assets/materials/facade_concrete_01/albedo.png",
	"concrete_roughness_tex": "res://assets/materials/facade_concrete_01/roughness.png",
	"tower_albedo_tex": "res://assets/materials/facade_tower_01/albedo.png",
	"tower_roughness_tex": "res://assets/materials/facade_tower_01/roughness.png",
	"tower_metallic_tex": "res://assets/materials/facade_tower_01/metallic.png",
	"roof_albedo_tex": "res://assets/materials/facade_brick_01/albedo.png",
	"roof_roughness_tex": "res://assets/materials/facade_brick_01/roughness.png",
}

const FLOAT_PARAMS := {
	"masonry_uv_scale": 0.21,
	"concrete_uv_scale": 0.18,
	"tower_uv_scale": 0.24,
	"roof_uv_scale": 0.16,
}


static func apply_to(mat: Material) -> void:
	if not mat is ShaderMaterial:
		return
	var shader_mat := mat as ShaderMaterial
	for param in FLOAT_PARAMS:
		shader_mat.set_shader_parameter(param, FLOAT_PARAMS[param])
	for param in TEXTURE_PATHS:
		var path: String = TEXTURE_PATHS[param]
		if ResourceLoader.exists(path):
			shader_mat.set_shader_parameter(param, load(path))
