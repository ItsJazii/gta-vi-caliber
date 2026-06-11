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
## Peak knee/elbow flexion (radians) at full stride. The driver scales these by
## the live hip/shoulder swing, so a slow walk bends gently and a sprint deeply.
const KNEE_AMPLITUDE: float = 0.95
const ELBOW_AMPLITUDE: float = 0.5
## Ankle roll (radians): toe lifts at heel-strike, points at toe-off. Subtle.
const ANKLE_AMPLITUDE: float = 0.32

## Skin tone; tweak per-NPC later for crowd variety.
@export var skin_color: Color = Color(0.86, 0.66, 0.54)
@export var shirt_color: Color = Color(0.22, 0.42, 0.78)
@export var pants_color: Color = Color(0.14, 0.16, 0.24)
@export var shoe_color: Color = Color(0.08, 0.08, 0.1)
@export var hair_color: Color = Color(0.16, 0.11, 0.07)
@export var eye_color: Color = Color(0.13, 0.09, 0.06)
## Applies the original Mara Vale hero treatment to the playable rig: charcoal
## cropped jacket, olive cargos, gloves, boots, strap, pendant, eyebrow scar and
## silver-streaked asymmetrical hair. Kept procedural so the player remains
## lightweight until a real authored GLB arrives.
@export var use_mara_hero_profile: bool = false
## When true, a random palette is drawn from the curated crowd swatches above
## before the body is built, so a street full of these reads as distinct people
## rather than clones. Leave false for the hero player (uses the colors above).
@export var randomize_palette: bool = false

var _skin: StandardMaterial3D
var _shirt: StandardMaterial3D
var _pants: StandardMaterial3D
var _shoe: StandardMaterial3D
var _hair: StandardMaterial3D
var _jacket: StandardMaterial3D
var _glove: StandardMaterial3D
var _strap: StandardMaterial3D
var _metal: StandardMaterial3D
var _scar: StandardMaterial3D
var _silver_hair: StandardMaterial3D
var _sclera: StandardMaterial3D
var _iris: StandardMaterial3D
var _mouth: StandardMaterial3D

# Articulated limb chains, filled by _ready, driven each frame in _process.
# Each leg: {hip, knee, amp}; each arm: {shoulder, elbow, amp}.
var _legs: Array = []
var _arms: Array = []
# Idle life: a gentle chest breath so a standing character is never a statue.
var _torso: MeshInstance3D
var _breath_t: float = 0.0


func _ready() -> void:
	if randomize_palette:
		_pick_random_palette()
	if use_mara_hero_profile:
		_apply_mara_palette()
	_build_materials()
	var rig: Node = get_parent()
	if rig == null:
		return
	_apply(rig, "Hips/Torso", HumanoidMesh.torso(), _shirt)
	_apply(rig, "Hips/Pelvis", HumanoidMesh.pelvis(), _pants)
	_apply(rig, "Hips/Neck", HumanoidMesh.neck(), _skin)
	_apply(rig, "Hips/Head", HumanoidMesh.head(), _skin)
	# Two-bone limbs: the animator still swings the hip/shoulder; the knee/elbow
	# bend is added on top from that same swing (see _process). Read the rig's
	# swing amplitudes so normalisation tracks the animator's tuning.
	var leg_amp: float = _rig_float(rig, "leg_amplitude", 0.7)
	var arm_amp: float = _rig_float(rig, "arm_amplitude", 0.5)
	_articulate_leg(rig, "Hips/HipL", "LegL", "FootL", leg_amp)
	_articulate_leg(rig, "Hips/HipR", "LegR", "FootR", leg_amp)
	_articulate_arm(rig, "Hips/ShoulderL", "ArmL", "HandL", arm_amp)
	_articulate_arm(rig, "Hips/ShoulderR", "ArmR", "HandR", arm_amp)
	_add_head_details(rig)
	if use_mara_hero_profile:
		_add_mara_details(rig)
	_torso = rig.get_node_or_null("Hips/Torso") as MeshInstance3D


func _process(delta: float) -> void:
	# A slow chest breath (~14/min) expanding the torso depth/width keeps a
	# standing character alive; it's masked by the bigger walk motion when moving.
	_breath_t += delta
	if _torso != null:
		var breath := sin(_breath_t * 1.5)
		_torso.scale = Vector3(1.0 + 0.016 * breath, 1.0, 1.0 + 0.024 * breath)
	# Knee/elbow flex derives from the live hip/shoulder swing, so it stays in
	# perfect lockstep with the animator without sharing a phase clock.
	for leg in _legs:
		var hip: Node3D = leg["hip"]
		var hip_angle: float = hip.rotation.x
		var swing := clampf(hip_angle / maxf(leg["amp"], 0.01), -1.0, 1.0)
		leg["knee"].rotation.x = -Locomotion.knee_flex_from_swing(swing, KNEE_AMPLITUDE)
		# Foot roll: cos(phase) = sqrt(1 - sin^2) with the sign taken from the
		# swing direction, so the sole stays level — toe up at heel-strike, down
		# at toe-off — without a separate phase clock. (sin(phase) = swing.)
		var direction := signf(hip_angle - float(leg["prev"]))
		leg["prev"] = hip_angle
		var cos_phase := sqrt(maxf(0.0, 1.0 - swing * swing)) * direction
		leg["ankle"].rotation.x = -cos_phase * ANKLE_AMPLITUDE
	for arm in _arms:
		var shoulder: Node3D = arm["shoulder"]
		var swing := clampf(shoulder.rotation.x / maxf(arm["amp"], 0.01), -1.0, 1.0)
		arm["elbow"].rotation.x = Locomotion.elbow_flex_from_swing(swing, ELBOW_AMPLITUDE)


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


func _apply_mara_palette() -> void:
	skin_color = Color(0.70, 0.48, 0.36)
	shirt_color = Color(0.27, 0.31, 0.34)
	pants_color = Color(0.18, 0.23, 0.16)
	shoe_color = Color(0.035, 0.034, 0.035)
	hair_color = Color(0.045, 0.038, 0.035)
	eye_color = Color(0.18, 0.12, 0.075)


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
	_apply_detail_normal(_skin, HumanoidTextures.skin_normal(), 0.45, 7.0)

	_shirt = _fabric(shirt_color, 0.82, 0.12)
	_pants = _fabric(pants_color, 0.9, 0.06)
	_jacket = _fabric(Color(0.075, 0.082, 0.086), 0.78, 0.16)
	_glove = _leather(Color(0.025, 0.023, 0.022), 0.62)
	_strap = _leather(Color(0.06, 0.044, 0.034), 0.68)
	_metal = StandardMaterial3D.new()
	_metal.albedo_color = Color(0.72, 0.52, 0.25)
	_metal.metallic = 0.75
	_metal.roughness = 0.36
	_metal.cull_mode = BaseMaterial3D.CULL_DISABLED
	_scar = StandardMaterial3D.new()
	_scar.albedo_color = skin_color.darkened(0.18).lerp(Color(0.64, 0.36, 0.32), 0.45)
	_scar.roughness = 0.58
	_scar.cull_mode = BaseMaterial3D.CULL_DISABLED
	_silver_hair = StandardMaterial3D.new()
	_silver_hair.albedo_color = Color(0.66, 0.65, 0.62)
	_silver_hair.roughness = 0.55
	_silver_hair.cull_mode = BaseMaterial3D.CULL_DISABLED

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

	# Crowds wear varied hairstyles; the hero keeps the default crop.
	var hair_style := 0
	if randomize_palette:
		var hrng := RandomNumberGenerator.new()
		hrng.randomize()
		hair_style = hrng.randi() % 4
	var hair := MeshInstance3D.new()
	hair.mesh = HumanoidMesh.to_mesh(HumanoidMesh.hair(0.28, 0.13, hair_style))
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


func _add_mara_details(rig: Node) -> void:
	var hips: Node3D = rig.get_node_or_null("Hips") as Node3D
	if hips == null:
		return
	var jacket := _seg(
		HumanoidMesh.torso(0.46, 0.272, 0.17, 0.19, 0.135), _jacket, Vector3(0.0, 0.49, -0.006)
	)
	jacket.name = "MaraCroppedJacket"
	hips.add_child(jacket)

	var shirt_panel := _box("MaraVisibleShirt", Vector3(0.15, 0.42, 0.018), _shirt)
	shirt_panel.position = Vector3(0.0, 0.48, -0.145)
	hips.add_child(shirt_panel)

	var belt := _box("MaraBelt", Vector3(0.43, 0.035, 0.028), _strap)
	belt.position = Vector3(0.0, 0.06, -0.005)
	hips.add_child(belt)

	var strap := _box("MaraMessengerStrap", Vector3(0.055, 0.78, 0.028), _strap)
	strap.position = Vector3(-0.04, 0.42, -0.17)
	strap.rotation.z = -0.42
	hips.add_child(strap)

	var pendant_chain := _box("MaraPendantCord", Vector3(0.012, 0.15, 0.012), _strap)
	pendant_chain.position = Vector3(0.0, 0.47, -0.18)
	hips.add_child(pendant_chain)

	var pendant := _sphere(0.025, _metal)
	pendant.name = "MaraPendant"
	pendant.position = Vector3(0.0, 0.39, -0.185)
	pendant.scale = Vector3(0.8, 1.1, 0.25)
	hips.add_child(pendant)

	_add_cargo_pocket(rig, "Hips/HipL", 1.0)
	_add_cargo_pocket(rig, "Hips/HipR", -1.0)
	_add_mara_head_details(rig)


func _add_cargo_pocket(rig: Node, hip_path: String, side: float) -> void:
	var hip: Node3D = rig.get_node_or_null(hip_path) as Node3D
	if hip == null:
		return
	var pocket := _box("MaraCargoPocket", Vector3(0.075, 0.12, 0.028), _pants)
	pocket.position = Vector3(0.095 * side, -0.28, -0.04)
	pocket.rotation.z = 0.04 * side
	hip.add_child(pocket)
	var flap := _box("MaraCargoPocketFlap", Vector3(0.085, 0.022, 0.032), _jacket)
	flap.position = Vector3(0.095 * side, -0.215, -0.055)
	hip.add_child(flap)


func _add_mara_head_details(rig: Node) -> void:
	var head: MeshInstance3D = rig.get_node_or_null("Hips/Head") as MeshInstance3D
	if head == null:
		return
	var bang := _sphere(0.064, _hair)
	bang.name = "MaraAsymmetricBangs"
	bang.position = Vector3(-0.045, 0.052, -0.07)
	bang.rotation.z = -0.32
	bang.scale = Vector3(1.0, 0.48, 1.25)
	head.add_child(bang)

	var streak := _sphere(0.022, _silver_hair)
	streak.name = "MaraSilverHairStreak"
	streak.position = Vector3(-0.062, 0.043, -0.105)
	streak.rotation.z = -0.36
	streak.scale = Vector3(0.48, 1.65, 0.32)
	head.add_child(streak)

	var scar := _box("MaraEyebrowScar", Vector3(0.009, 0.048, 0.006), _scar)
	scar.position = Vector3(-0.05, 0.02, -0.121)
	scar.rotation.z = -0.45
	head.add_child(scar)


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


## Replace a single-segment leg with thigh + knee joint + shin + foot. The hip
## node (swung by the animator) keeps the thigh; a runtime Knee node carries the
## shin and foot and is bent each frame. The old one-piece meshes are only
## hidden, so anything reading their transform (e.g. footstep position) still
## works. Pivots match the original rig: knee at y=-0.41, ankle at y=-0.82.
func _articulate_leg(
	rig: Node, hip_path: String, leg_child: String, foot_child: String, amp: float
) -> void:
	var hip: Node3D = rig.get_node_or_null(hip_path) as Node3D
	if hip == null:
		return
	_hide(rig, hip_path + "/" + leg_child)
	_hide(rig, hip_path + "/" + foot_child)
	hip.add_child(
		_seg(HumanoidMesh.limb(0.44, 0.092, 0.09, 0.062, 14, 16), _pants, Vector3(0, -0.205, 0))
	)
	var knee := Node3D.new()
	knee.name = "Knee"
	knee.position = Vector3(0, -0.41, 0)
	hip.add_child(knee)
	knee.add_child(
		_seg(HumanoidMesh.limb(0.42, 0.058, 0.056, 0.045, 14, 16), _pants, Vector3(0, -0.205, 0))
	)
	var ankle := Node3D.new()
	ankle.name = "Ankle"
	ankle.position = Vector3(0, -0.41, 0)
	knee.add_child(ankle)
	ankle.add_child(_seg(HumanoidMesh.foot(), _shoe, Vector3(0, 0, 0.06)))
	_legs.append({"hip": hip, "knee": knee, "ankle": ankle, "amp": amp, "prev": 0.0})


## Replace a single-segment arm with upper arm + elbow joint + forearm + hand.
## Forearm/hand are skin (rolled sleeves) so the elbow break reads clearly.
## Pivots match the rig: elbow at y=-0.33, wrist at y=-0.66.
func _articulate_arm(
	rig: Node, sh_path: String, arm_child: String, hand_child: String, amp: float
) -> void:
	var shoulder: Node3D = rig.get_node_or_null(sh_path) as Node3D
	if shoulder == null:
		return
	_hide(rig, sh_path + "/" + arm_child)
	_hide(rig, sh_path + "/" + hand_child)
	shoulder.add_child(
		_seg(HumanoidMesh.limb(0.36, 0.062, 0.062, 0.05, 12, 14), _shirt, Vector3(0, -0.165, 0))
	)
	var elbow := Node3D.new()
	elbow.name = "Elbow"
	elbow.position = Vector3(0, -0.33, 0)
	shoulder.add_child(elbow)
	elbow.add_child(
		_seg(HumanoidMesh.limb(0.34, 0.05, 0.048, 0.04, 12, 14), _skin, Vector3(0, -0.155, 0))
	)
	var hand_mat: Material = _glove if use_mara_hero_profile else _skin
	elbow.add_child(_seg(HumanoidMesh.hand(), hand_mat, Vector3(0, -0.33, 0)))
	_arms.append({"shoulder": shoulder, "elbow": elbow, "amp": amp})


func _seg(geo: Dictionary, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = HumanoidMesh.to_mesh(geo)
	mi.material_override = mat
	mi.position = pos
	return mi


func _box(node_name: String, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.name = node_name
	mi.mesh = box
	mi.material_override = mat
	return mi


func _hide(rig: Node, path: String) -> void:
	var node: MeshInstance3D = rig.get_node_or_null(path) as MeshInstance3D
	if node != null:
		node.visible = false


func _rig_float(rig: Node, prop: String, fallback: float) -> float:
	var v: Variant = rig.get(prop)
	return float(v) if v != null else fallback


func _fabric(color: Color, roughness: float, rim: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = 0.0
	mat.rim_enabled = rim > 0.0
	mat.rim = rim
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_apply_detail_normal(mat, HumanoidTextures.fabric_normal(), 0.6, 11.0)
	return mat


func _leather(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_apply_detail_normal(mat, HumanoidTextures.fabric_normal(), 0.3, 18.0)
	return mat


## Attach a procedural detail-normal map with local-space triplanar projection —
## no UVs or tangents needed (the procedural meshes carry neither). scale is the
## triplanar tiling density; strength how pronounced the micro-relief reads.
func _apply_detail_normal(
	mat: StandardMaterial3D, tex: Texture2D, strength: float, scale: float
) -> void:
	mat.normal_enabled = true
	mat.normal_texture = tex
	mat.normal_scale = strength
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(scale, scale, scale)
