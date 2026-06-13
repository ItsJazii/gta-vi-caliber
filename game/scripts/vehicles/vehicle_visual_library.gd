class_name VehicleVisualLibrary
extends RefCounted
## Shared access to the two production vehicle models. Playable cars use the
## full-detail scenes; ambient traffic uses decimated meshes with the original
## PBR material copied from the matching full-detail model.

enum Variant { SPORT_COUPE, CLASSIC_SEDAN }

## The decimated sedan extends about 2.8 cm below its origin. This small shared
## lift keeps both ambient variants above the road without visible floating.
const MODEL_FLOOR_OFFSET_Y: float = 0.03

const PLAYABLE_SCENES: Array[PackedScene] = [
	preload("res://assets/vehicles/coastal_sport_coupe/coastal_sport_coupe.glb"),
	preload("res://assets/vehicles/coastal_classic_sedan/coastal_classic_sedan.glb"),
]
const TRAFFIC_SCENES: Array[PackedScene] = [
	preload("res://assets/vehicles/coastal_sport_coupe/coastal_sport_coupe_traffic.glb"),
	preload("res://assets/vehicles/coastal_classic_sedan/coastal_classic_sedan_traffic.glb"),
]


static func variant_count() -> int:
	return PLAYABLE_SCENES.size()


static func normalize_variant(variant: int) -> int:
	return posmod(variant, variant_count())


static func instantiate_playable(variant: int) -> Node3D:
	return PLAYABLE_SCENES[normalize_variant(variant)].instantiate() as Node3D


static func instantiate_traffic(variant: int) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = traffic_mesh(variant)
	visual.position.y = MODEL_FLOOR_OFFSET_Y
	return visual


static func traffic_mesh(variant: int) -> Mesh:
	var index := normalize_variant(variant)
	var traffic_root := TRAFFIC_SCENES[index].instantiate()
	var traffic_visual := first_mesh_instance(traffic_root)
	var playable_root := PLAYABLE_SCENES[index].instantiate()
	var playable_visual := first_mesh_instance(playable_root)
	if traffic_visual == null or playable_visual == null or traffic_visual.mesh == null:
		traffic_root.free()
		playable_root.free()
		return null
	var mesh := traffic_visual.mesh
	for surface in mesh.get_surface_count():
		var source_surface := mini(surface, playable_visual.mesh.get_surface_count() - 1)
		mesh.surface_set_material(surface, playable_visual.get_active_material(source_surface))
	traffic_root.free()
	playable_root.free()
	return mesh


static func first_mesh_instance(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root as MeshInstance3D
	for child in root.find_children("*", "MeshInstance3D", true, false):
		return child as MeshInstance3D
	return null
