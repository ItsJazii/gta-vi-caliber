extends RefCounted
## Contract guard for Ocean v2 foam. The whitecap foam lives only in the GPU
## shader (no CPU twin), so these tests parse the shader source and the Ocean
## node to lock in that open-water whitecaps stay DECOUPLED from the shoreline
## band — the whole point of the Jacobian-cap rework. A future edit that
## re-merges them, or drops the push from ocean.gd, fails here instead of
## silently flat-lining the sea back to plastic.

const SHADER_PATH := "res://shaders/ocean.gdshader"
const OCEAN_SCRIPT := "res://scripts/world/ocean.gd"


func _shader_src() -> String:
	return FileAccess.get_file_as_string(SHADER_PATH)


func _ocean_src() -> String:
	return FileAccess.get_file_as_string(OCEAN_SCRIPT)


func test_shader_declares_decoupled_whitecap_uniforms() -> bool:
	var src := _shader_src()
	return (
		src.contains("uniform float u_whitecap_strength")
		and src.contains("uniform float u_whitecap_coverage")
	)


func test_shader_keeps_shore_band_strength_separate() -> bool:
	# The shoreline band must still have its own knob distinct from whitecaps.
	var src := _shader_src()
	return src.contains("uniform float u_foam_strength") and src.contains("u_whitecap_strength")


func test_shader_has_gerstner_jacobian() -> bool:
	# Whitecaps key off the horizontal Jacobian (where the wave field folds),
	# not raw crest height. Guard the function exists and is used in fragment.
	var src := _shader_src()
	return src.contains("float gerstner_jacobian(") and src.contains("gerstner_jacobian(v_param")


func test_ocean_node_pushes_both_whitecap_params() -> bool:
	var src := _ocean_src()
	return (
		src.contains('set_shader_parameter("u_whitecap_strength"')
		and src.contains('set_shader_parameter("u_whitecap_coverage"')
	)


func test_ocean_node_exports_whitecap_knobs() -> bool:
	var src := _ocean_src()
	return src.contains("var whitecap_strength") and src.contains("var whitecap_coverage")
