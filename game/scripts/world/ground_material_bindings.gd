class_name GroundMaterialBindings
extends RefCounted
## Shared streamed-world ground material bindings. Keeps the sidewalk and sand
## texture hookups in one place so the district loader, Florida backdrop, and
## tests agree on which shipped assets should feed the shader paths.

const SIDEWALK_TEXTURE_PATHS := {
	"detail_tex": "res://assets/materials/concrete_sidewalk_01/albedo.png",
	"detail_roughness_tex": "res://assets/materials/concrete_sidewalk_01/roughness.png",
}

const SIDEWALK_FLOAT_PARAMS := {
	"detail_uv_scale": 0.32,
}

const SAND_TEXTURE_PATHS := {
	"detail_tex": "res://assets/textures/sand_albedo.png",
}

const SAND_FLOAT_PARAMS := {
	"detail_uv_scale": 0.045,
}


static func apply_to_sidewalk(mat: Material) -> void:
	_apply(mat, SIDEWALK_FLOAT_PARAMS, SIDEWALK_TEXTURE_PATHS)


static func apply_to_sand(mat: Material) -> void:
	_apply(mat, SAND_FLOAT_PARAMS, SAND_TEXTURE_PATHS)


static func _apply(mat: Material, float_params: Dictionary, texture_paths: Dictionary) -> void:
	if not mat is ShaderMaterial:
		return
	var shader_mat := mat as ShaderMaterial
	for param in float_params:
		shader_mat.set_shader_parameter(param, float_params[param])
	for param in texture_paths:
		var path: String = texture_paths[param]
		if ResourceLoader.exists(path):
			shader_mat.set_shader_parameter(param, load(path))
