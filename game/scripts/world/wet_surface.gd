class_name WetSurface
extends RefCounted
## Maps a wetness value (0 dry … 1 soaked, from Weather) to surface look: wet
## ground is darker, smoother (lower roughness), and more reflective. Pure math
## unit-tests headless (tests/unit/test_wet_surface.gd); apply_to() pushes the
## result onto a StandardMaterial3D for the rendering layer.


## Roughness drops as the surface wets — puddles are near-mirror smooth.
static func roughness(dry_roughness: float, wetness: float) -> float:
	return lerpf(dry_roughness, dry_roughness * 0.2, clampf(wetness, 0.0, 1.0))


## Wet surfaces look darker.
static func albedo_scale(wetness: float) -> float:
	return lerpf(1.0, 0.65, clampf(wetness, 0.0, 1.0))


## Specular reflectivity rises with wetness.
static func reflectivity(wetness: float) -> float:
	return lerpf(0.1, 0.7, clampf(wetness, 0.0, 1.0))


## Apply the wet look to a material, given its dry albedo and roughness.
static func apply_to(
	material: StandardMaterial3D, dry_albedo: Color, dry_roughness: float, wetness: float
) -> void:
	var scale := albedo_scale(wetness)
	material.albedo_color = Color(
		dry_albedo.r * scale, dry_albedo.g * scale, dry_albedo.b * scale, dry_albedo.a
	)
	material.roughness = roughness(dry_roughness, wetness)
	material.metallic_specular = reflectivity(wetness)
