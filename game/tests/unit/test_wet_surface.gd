extends RefCounted
## Unit tests for WetSurface — wetness → look mapping.


func test_dry_is_identity_roughness() -> bool:
	return absf(WetSurface.roughness(1.0, 0.0) - 1.0) < 0.001


func test_wet_lowers_roughness() -> bool:
	return WetSurface.roughness(1.0, 1.0) < WetSurface.roughness(1.0, 0.0)


func test_wet_darkens_albedo() -> bool:
	return WetSurface.albedo_scale(1.0) < WetSurface.albedo_scale(0.0)


func test_wet_raises_reflectivity() -> bool:
	return WetSurface.reflectivity(1.0) > WetSurface.reflectivity(0.0)


func test_wetness_is_clamped() -> bool:
	return (
		absf(WetSurface.roughness(1.0, 5.0) - WetSurface.roughness(1.0, 1.0)) < 0.001
		and absf(WetSurface.albedo_scale(-3.0) - WetSurface.albedo_scale(0.0)) < 0.001
	)


func test_apply_to_sets_material() -> bool:
	var mat := StandardMaterial3D.new()
	WetSurface.apply_to(mat, Color(0.5, 0.5, 0.5), 1.0, 1.0)
	return mat.roughness < 0.5 and mat.albedo_color.r < 0.5
