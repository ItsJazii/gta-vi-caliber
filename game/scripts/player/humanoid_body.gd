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

## Curated swatches so randomized crowds stay believable — real human skin,
## hair and everyday-clothing hues only, never neon. One entry is picked per
## channel; shirts get the widest range because that's what the eye tracks.
const SKIN_TONES: Array[Color] = [
	Color(0.93, 0.78, 0.68),
	Color(0.86, 0.66, 0.54),
	Color(0.74, 0.55, 0.43),
	Color(0.56, 0.40, 0.30),
	Color(0.40, 0.27, 0.20),
	Color(0.30, 0.20, 0.15),
]
const HAIR_COLORS: Array[Color] = [
	Color(0.05, 0.04, 0.03),  # black
	Color(0.16, 0.11, 0.07),  # dark brown
	Color(0.33, 0.22, 0.12),  # brown
	Color(0.55, 0.40, 0.22),  # dark blond
	Color(0.72, 0.58, 0.36),  # blond
	Color(0.62, 0.60, 0.58),  # grey
	Color(0.45, 0.16, 0.08),  # auburn
]
const SHIRT_COLORS: Array[Color] = [
	Color(0.22, 0.42, 0.78),
	Color(0.78, 0.24, 0.26),
	Color(0.90, 0.88, 0.84),
	Color(0.18, 0.20, 0.24),
	Color(0.20, 0.52, 0.36),
	Color(0.86, 0.62, 0.20),
	Color(0.50, 0.30, 0.62),
	Color(0.30, 0.62, 0.70),
]
const PANTS_COLORS: Array[Color] = [
	Color(0.14, 0.16, 0.24),  # navy
	Color(0.20, 0.20, 0.22),  # charcoal
	Color(0.32, 0.28, 0.22),  # khaki
	Color(0.10, 0.10, 0.11),  # black
	Color(0.36, 0.40, 0.50),  # faded denim
]

## Skin tone; tweak per-NPC later for crowd variety.
@export var skin_color: Color = Color(0.86, 0.66, 0.54)
@export var shirt_color: Color = Color(0.22, 0.42, 0.78)
@export var pants_color: Color = Color(0.14, 0.16, 0.24)
@export var shoe_color: Color = Color(0.08, 0.08, 0.1)
@export var hair_color: Color = Color(0.16, 0.11, 0.07)
@export var eye_color: Color = Color(0.13, 0.09, 0.06)
## When true, a random palette is drawn from the curated crowd swatches above
## before the body is built, so a street full of these reads as distinct people
## rather than clones. Leave false for the hero player (uses the colors above).
@export var randomize_palette: bool = false

var _skin: StandardMaterial3D
var _shirt: StandardMaterial3D
var _pants: StandardMaterial3D
var _shoe: StandardMaterial3D
var _hair: StandardMaterial3D
var _sclera: StandardMaterial3D
var _iris: StandardMaterial3D
var _mouth: StandardMaterial3D


func _ready() -> void:
	if randomize_palette:
		_pick_random_palette()
	_build_materials()
	var rig: Node = get_parent()
	if rig == null:
		return
	_apply(rig, "Hips/Torso", HumanoidMesh.torso(), _shirt)
	_apply(rig, "Hips/Pelvis", HumanoidMesh.pelvis(), _pants)
	_apply(rig, "Hips/Neck", HumanoidMesh.neck(), _skin)
	_apply(rig, "Hips/Head", HumanoidMesh.head(), _skin)
	_apply(rig, "Hips/ShoulderL/ArmL", HumanoidMesh.arm(), _shirt)
	_apply(rig, "Hips/ShoulderR/ArmR", HumanoidMesh.arm(), _shirt)
	_apply(rig, "Hips/ShoulderL/HandL", HumanoidMesh.hand(), _skin)
	_apply(rig, "Hips/ShoulderR/HandR", HumanoidMesh.hand(), _skin)
	_apply(rig, "Hips/HipL/LegL", HumanoidMesh.leg(), _pants)
	_apply(rig, "Hips/HipR/LegR", HumanoidMesh.leg(), _pants)
	_apply(rig, "Hips/HipL/FootL", HumanoidMesh.foot(), _shoe)
	_apply(rig, "Hips/HipR/FootR", HumanoidMesh.foot(), _shoe)
	_add_head_details(rig)


func _apply(rig: Node, path: String, geo: Dictionary, mat: Material) -> void:
	var node: MeshInstance3D = rig.get_node_or_null(path) as MeshInstance3D
	if node == null:
		return
	var mesh := HumanoidMesh.to_mesh(geo)
	if mesh == null:
		return
	node.mesh = mesh
	node.material_override = mat


## Draw one swatch per channel from the curated arrays and nudge each by a small
## random brightness/hue jitter, so even two pedestrians who roll the same shirt
## swatch aren't pixel-identical. Eyes track hair; shoes stay near-black.
func _pick_random_palette() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	skin_color = _jitter(SKIN_TONES[rng.randi() % SKIN_TONES.size()], rng, 0.05)
	hair_color = _jitter(HAIR_COLORS[rng.randi() % HAIR_COLORS.size()], rng, 0.04)
	shirt_color = _jitter(SHIRT_COLORS[rng.randi() % SHIRT_COLORS.size()], rng, 0.06)
	pants_color = _jitter(PANTS_COLORS[rng.randi() % PANTS_COLORS.size()], rng, 0.05)
	eye_color = HAIR_COLORS[rng.randi() % 3]  # eyes among the darker hair hues


## Clamp a per-channel additive jitter so swatches stay in believable range.
func _jitter(c: Color, rng: RandomNumberGenerator, amount: float) -> Color:
	var d := rng.randf_range(-amount, amount)
	return Color(clampf(c.r + d, 0.0, 1.0), clampf(c.g + d, 0.0, 1.0), clampf(c.b + d, 0.0, 1.0))


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

	_hair = StandardMaterial3D.new()
	_hair.albedo_color = hair_color
	_hair.roughness = 0.62
	_hair.cull_mode = BaseMaterial3D.CULL_DISABLED

	_sclera = StandardMaterial3D.new()
	_sclera.albedo_color = Color(0.93, 0.93, 0.91)
	_sclera.roughness = 0.32

	_iris = StandardMaterial3D.new()
	_iris.albedo_color = eye_color
	_iris.roughness = 0.18
	_iris.metallic = 0.0

	_mouth = StandardMaterial3D.new()
	_mouth.albedo_color = Color(0.5, 0.28, 0.26)
	_mouth.roughness = 0.5


## Parent the hair shell, both eyes (sclera + iris) and a nose to the head so the
## character reads as a person with a front, not a featureless mannequin. The
## head faces -Z, so the features sit on the head's -Z side. Built at runtime as
## head children, which keeps the scene file free of a dozen tiny face nodes.
func _add_head_details(rig: Node) -> void:
	var head: MeshInstance3D = rig.get_node_or_null("Hips/Head") as MeshInstance3D
	if head == null:
		return

	var hair := MeshInstance3D.new()
	hair.mesh = HumanoidMesh.to_mesh(HumanoidMesh.hair())
	hair.material_override = _hair
	head.add_child(hair)

	# Eyes sit at mid-face, just below the hairline so the bangs don't cover them.
	for side: float in [-1.0, 1.0]:
		var sclera := _sphere(0.024, _sclera)
		sclera.position = Vector3(0.046 * side, -0.015, -0.088)
		sclera.scale = Vector3(1.0, 0.74, 0.66)
		head.add_child(sclera)
		var iris := _sphere(0.0125, _iris)
		iris.position = Vector3(0.047 * side, -0.016, -0.108)
		head.add_child(iris)
		var brow := _sphere(0.022, _hair)
		brow.position = Vector3(0.046 * side, 0.012, -0.098)
		brow.scale = Vector3(1.1, 0.28, 0.5)
		head.add_child(brow)

	var nose := _sphere(0.02, _skin)
	nose.position = Vector3(0.0, -0.052, -0.1)
	nose.scale = Vector3(0.8, 1.45, 1.55)
	head.add_child(nose)

	var mouth := _sphere(0.016, _mouth)
	mouth.position = Vector3(0.0, -0.09, -0.092)
	mouth.scale = Vector3(1.9, 0.5, 0.55)
	head.add_child(mouth)


func _sphere(radius: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = mat
	return mi


func _fabric(color: Color, roughness: float, rim: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = 0.0
	mat.rim_enabled = rim > 0.0
	mat.rim = rim
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
