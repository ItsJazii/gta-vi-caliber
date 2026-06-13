class_name CoastalPropPlacements
extends Node3D
## Instantiates the imported coastal set dressing around the playable spawn.

const PROP_SCENES: Dictionary = {
	CoastalPropLayout.PALM_PLANTER:
	preload("res://assets/environment/coastal_props/palm_planter.glb"),
	CoastalPropLayout.PALM_TREE: preload("res://assets/environment/coastal_props/palm_tree.glb"),
	CoastalPropLayout.STREET_LAMP:
	preload("res://assets/environment/coastal_props/street_lamp.glb"),
}


func _ready() -> void:
	for spec in CoastalPropLayout.placements():
		_add_prop(spec)


func _add_prop(spec: Dictionary) -> void:
	var kind: StringName = spec["kind"]
	var packed := PROP_SCENES.get(kind) as PackedScene
	if packed == null:
		push_error("CoastalPropPlacements: no scene for %s" % kind)
		return
	var instance := packed.instantiate() as Node3D
	if instance == null:
		push_error("CoastalPropPlacements: %s has no Node3D root" % kind)
		return
	instance.name = spec["name"]
	instance.position = spec["position"]
	instance.rotation.y = deg_to_rad(float(spec["yaw_degrees"]))
	instance.scale = Vector3.ONE * float(spec["scale"])
	instance.add_to_group("coastal_props")
	instance.add_to_group("coastal_prop_%s" % kind)
	add_child(instance)
