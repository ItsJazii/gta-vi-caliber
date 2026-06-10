class_name HumanoidBody
extends Node3D
## Swaps the rig's greybox boxes for premium procedural body geometry and applies
## PBR skin/fabric materials, once, in _ready().
##
## Sits as a child of the rig root (the CharacterAnimator). It only rewrites the
## `mesh` and `material_override` of the existing body MeshInstance3D nodes — no
## transform, no joint, and the animator are touched, so swing/lean/bob keep
## working exactly as before but on a smooth, rounded human form. Every lookup is
## null-guarded: if the rig hierarchy is mid-edit by another contributor, missing
## parts are skipped instead of crashing the headless gate.

## Skin tone; tweak per-NPC later for crowd variety.
@export var skin_color: Color = Color(0.86, 0.66, 0.54)
@export var shirt_color: Color = Color(0.22, 0.42, 0.78)
@export var pants_color: Color = Color(0.14, 0.16, 0.24)
@export var shoe_color: Color = Color(0.08, 0.08, 0.1)

var _skin: StandardMaterial3D
var _shirt: StandardMaterial3D
var _pants: StandardMaterial3D
var _shoe: StandardMaterial3D


func _ready() -> void:
	_build_materials()
	var rig: Node = get_parent()
	if rig == null:
		return
	_apply(rig, "Hips/Torso", HumanoidMesh.torso(), _shirt)
	_apply(rig, "Hips/Pelvis", HumanoidMesh.pelvis(), _pants)
	_apply(rig, "Hips/Head", HumanoidMesh.head(), _skin)
	_apply(rig, "Hips/ShoulderL/ArmL", HumanoidMesh.arm(), _shirt)
	_apply(rig, "Hips/ShoulderR/ArmR", HumanoidMesh.arm(), _shirt)
	_apply(rig, "Hips/ShoulderL/HandL", HumanoidMesh.hand(), _skin)
	_apply(rig, "Hips/ShoulderR/HandR", HumanoidMesh.hand(), _skin)
	_apply(rig, "Hips/HipL/LegL", HumanoidMesh.leg(), _pants)
	_apply(rig, "Hips/HipR/LegR", HumanoidMesh.leg(), _pants)
	_apply(rig, "Hips/HipL/FootL", HumanoidMesh.foot(), _shoe)
	_apply(rig, "Hips/HipR/FootR", HumanoidMesh.foot(), _shoe)


func _apply(rig: Node, path: String, geo: Dictionary, mat: Material) -> void:
	var node: MeshInstance3D = rig.get_node_or_null(path) as MeshInstance3D
	if node == null:
		return
	var mesh := HumanoidMesh.to_mesh(geo)
	if mesh == null:
		return
	node.mesh = mesh
	node.material_override = mat


func _build_materials() -> void:
	_skin = StandardMaterial3D.new()
	_skin.albedo_color = skin_color
	_skin.roughness = 0.45
	_skin.metallic = 0.0
	# Subsurface scattering gives skin its soft, light-permeable falloff.
	_skin.subsurf_scatter_enabled = true
	_skin.subsurf_scatter_strength = 0.30
	# A faint rim picks out the silhouette against the sky, as flesh does.
	_skin.rim_enabled = true
	_skin.rim = 0.35
	_skin.rim_tint = 0.4
	_skin.cull_mode = BaseMaterial3D.CULL_DISABLED

	_shirt = _fabric(shirt_color, 0.82, 0.12)
	_pants = _fabric(pants_color, 0.9, 0.06)

	_shoe = StandardMaterial3D.new()
	_shoe.albedo_color = shoe_color
	_shoe.roughness = 0.55
	_shoe.metallic = 0.1
	_shoe.cull_mode = BaseMaterial3D.CULL_DISABLED


func _fabric(color: Color, roughness: float, rim: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = 0.0
	mat.rim_enabled = rim > 0.0
	mat.rim = rim
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
