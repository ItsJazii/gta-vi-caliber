class_name BoatBody
extends Node3D
## Swaps the greybox boat hull box for a sleek procedural hull, once in _ready.
##
## Sits as a child of the Boat (RigidBody3D). Only rewrites the Hull mesh/material;
## the float points, collision and Console are untouched. Null-guarded so a
## mid-edit scene can't crash the headless gate.

@export var hull_color: Color = Color(0.93, 0.93, 0.9)


func _ready() -> void:
	var boat: Node = get_parent()
	if boat == null:
		return
	var hull: MeshInstance3D = boat.get_node_or_null("Hull") as MeshInstance3D
	if hull == null:
		return
	hull.mesh = BoatMesh.to_mesh(BoatMesh.hull())
	hull.material_override = _gelcoat()
	hull.position = Vector3.ZERO  # hull authored with keel near y=0


func _gelcoat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = hull_color
	mat.metallic = 0.2
	mat.roughness = 0.22
	mat.rim_enabled = true
	mat.rim = 0.2
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
