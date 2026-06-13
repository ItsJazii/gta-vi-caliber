extends RefCounted
## Guards for the CloudLayer sky sheet. The cloud look is GPU-only, so these
## parse the shader + node source to lock in that the sheet stays transparent,
## unshaded, distance-faded, and wired to the cloud shader — a regression here
## would flat-line the playable map's sky back to a bare gradient.

const SHADER_PATH := "res://shaders/cloud_plane.gdshader"
const NODE_PATH := "res://scripts/world/cloud_layer.gd"
const BACKDROP_PATH := "res://scripts/world/florida_backdrop.gd"


func test_shader_is_transparent_unshaded_sheet() -> bool:
	var src := FileAccess.get_file_as_string(SHADER_PATH)
	return src.contains("render_mode unshaded") and src.contains("ALPHA =")


func test_shader_exposes_coverage_and_distance_fade() -> bool:
	var src := FileAccess.get_file_as_string(SHADER_PATH)
	return (
		src.contains("uniform float coverage")
		and src.contains("fade_start")
		and src.contains("fade_end")
	)


func test_node_loads_cloud_shader_and_sets_coverage() -> bool:
	var src := FileAccess.get_file_as_string(NODE_PATH)
	return (
		src.contains('load("res://shaders/cloud_plane.gdshader")')
		and src.contains('set_shader_parameter("coverage"')
	)


func test_node_exports_tuning_knobs() -> bool:
	var src := FileAccess.get_file_as_string(NODE_PATH)
	return src.contains("var altitude") and src.contains("var coverage")


func test_backdrop_builds_a_cloud_layer() -> bool:
	# The playable map only gets a sky if FloridaBackdrop actually instances it.
	var src := FileAccess.get_file_as_string(BACKDROP_PATH)
	return src.contains("CloudLayer.new()") and src.contains("_build_clouds()")
