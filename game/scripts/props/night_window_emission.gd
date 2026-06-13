class_name NightWindowEmission
extends Node
## Drives every emissive StandardMaterial3D found under this node's parent from
## the shared day/night clock (StreetlightSwitch.night_level, published by
## SkyController), so window glow follows the world like the live facade
## shaders do. GLB-imported materials carry a STATIC emission and would glow at
## noon otherwise — the asset gauntlet's time sweep caught exactly that.
## Add as a sibling AFTER the model so the imported materials exist at _ready.

var _materials: Array[StandardMaterial3D] = []
var _full_energy := PackedFloat32Array()


func _ready() -> void:
	for mesh in get_parent().find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mat != null and mat.emission_enabled and not _materials.has(mat):
				_materials.append(mat)
				_full_energy.append(mat.emission_energy_multiplier)


func _process(_delta: float) -> void:
	for i in _materials.size():
		_materials[i].emission_energy_multiplier = StreetlightSwitch.lamp_energy(
			StreetlightSwitch.night_level, _full_energy[i]
		)
