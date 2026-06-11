class_name HumanoidBody
extends Node3D

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
const BLINK_INTERVAL: float = 3.8
const BLINK_DURATION: float = 0.16
const MARA_SOFT_MOTION_RATE: float = 9.0

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
## Optional real imported Mara mesh. Current generated GLBs are static meshes
## (no skin/animation), so this renders as a high-detail shell while the
## procedural rig remains the animated playable body.
@export var imported_mara_scene: PackedScene
@export var imported_mara_offset: Vector3 = Vector3(0.0, 0.075, 0.0)
@export var imported_mara_scale: float = 1.0
@export var hide_procedural_when_imported: bool = false
## Hybrid quality mode: the generated GLB has a strong front projection but an
## unfinished rear shell. Show it for front/inspection views; use the clean
## animated procedural Mara rig for normal rear third-person gameplay.
@export var switch_imported_mara_by_camera: bool = false
## Show the imported front-projection GLB only when the camera is clearly in
## front of Mara; hide it only once the camera is clearly behind. The gap between
## these thresholds is deliberate hysteresis so side-orbiting never flickers.
@export var imported_mara_front_dot: float = 0.1
@export var imported_mara_rear_dot: float = -0.1
## Hide tiny Mara-specific trim/gear beyond this distance. The main body,
## limbs, jacket shell, and imported front projection remain visible.
@export var cosmetic_lod_distance: float = 22.0
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
var _blink_t: float = 0.0
var _eyelids: Array[MeshInstance3D] = []
var _mara_cosmetics: Array[MeshInstance3D] = []
var _mara_soft_parts: Array[Dictionary] = []
var _rig: Node = null
var _imported_visual: Node3D = null
var _procedural_visible: bool = true
var _show_imported_mara: bool = false


func _ready() -> void:
	if randomize_palette:
		_pick_random_palette()
	if use_mara_hero_profile:
		_apply_mara_palette()
	_build_materials()
	var rig: Node = get_parent()
	if rig == null:
		return
	_rig = rig
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
		_add_imported_mara_mesh(rig)
	_torso = rig.get_node_or_null("Hips/Torso") as MeshInstance3D


func _process(delta: float) -> void:
	# A slow chest breath (~14/min) expanding the torso depth/width keeps a
	# standing character alive; it's masked by the bigger walk motion when moving.
	_breath_t += delta
	if _torso != null:
		var breath := sin(_breath_t * 1.5)
		_torso.scale = Vector3(1.0 + 0.016 * breath, 1.0, 1.0 + 0.024 * breath)
	_update_blink(delta)
	_update_imported_mara_visibility()
	_update_mara_cosmetic_lod()
	_update_mara_soft_motion(delta)
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
	shirt_color = Color(0.025, 0.03, 0.032)
	pants_color = Color(0.18, 0.23, 0.16)
	shoe_color = Color(0.035, 0.034, 0.035)
	hair_color = Color(0.045, 0.038, 0.035)
	eye_color = Color(0.18, 0.12, 0.075)


func _build_materials() -> void:
	_skin = StandardMaterial3D.new()
	_skin.albedo_color = skin_color
	_skin.roughness = 0.45
	_skin.metallic = 0.0
	# Skin-mode subsurface scattering + reddish transmittance: light scatters
	# through and reddens in thin areas (ears, nose), the way real flesh does —
	# the single biggest lever for skin looking like skin rather than plastic.
	_skin.subsurf_scatter_enabled = true
	_skin.subsurf_scatter_skin_mode = true
	_skin.subsurf_scatter_strength = 0.5
	_skin.subsurf_scatter_transmittance_enabled = true
	_skin.subsurf_scatter_transmittance_color = Color(0.9, 0.38, 0.3)
	_skin.subsurf_scatter_transmittance_depth = 0.35
	_skin.subsurf_scatter_transmittance_boost = 0.2
	# A faint rim picks out the silhouette against the sky, as flesh does.
	_skin.rim_enabled = true
	_skin.rim = 0.35
	_skin.rim_tint = 0.4
	_skin.clearcoat_enabled = true
	_skin.clearcoat = 0.16
	_skin.clearcoat_roughness = 0.38
	_skin.cull_mode = BaseMaterial3D.CULL_DISABLED
	_skin.set_meta("mara_surface_profile", "skin")
	_apply_detail_normal(_skin, HumanoidTextures.skin_normal(), 0.45, 7.0)
	# Photoreal AI-generated skin albedo (Codex image gen; see docs/ASSETS.md) —
	# real pores and tone variation, tinted by each character's skin_color so the
	# hero, Mara and palette-varied crowds all keep their own complexion.
	var skin_tex := load("res://assets/textures/skin_albedo.png") as Texture2D
	if skin_tex != null:
		_skin.albedo_texture = skin_tex
		# Tint lightly toward white so the warm photoreal texture isn't double-warmed
		# into orange, while keeping a hint of each character's complexion.
		_skin.albedo_color = skin_color.lerp(Color.WHITE, 0.7)
	else:
		_skin.albedo_texture = HumanoidTextures.skin_albedo()

	var leather_tex := load("res://assets/textures/leather.png") as Texture2D
	# Cotton tints to each shirt colour (keeps crowd variety + adds knit detail).
	# Mara's hero jacket/pants stay on the procedural cloth albedo because the
	# tile-photo denim/leather textures are too bright for her charcoal silhouette.
	_shirt = _fabric(
		shirt_color,
		0.82,
		0.08 if use_mara_hero_profile else 0.12,
		null if use_mara_hero_profile else load("res://assets/textures/cotton.png") as Texture2D,
		not use_mara_hero_profile
	)
	_pants = _fabric(
		(
			pants_color.darkened(0.35)
			if use_mara_hero_profile
			else pants_color.lerp(Color.WHITE, 0.55)
		),
		0.9,
		0.06,
		null if use_mara_hero_profile else load("res://assets/textures/denim.png") as Texture2D,
		not use_mara_hero_profile
	)
	_jacket = _fabric(Color(0.025, 0.03, 0.032), 0.82, 0.08, null, false)
	_glove = _leather(Color(0.018, 0.017, 0.016), 0.66, leather_tex)
	_strap = _leather(Color(0.045, 0.034, 0.026), 0.72, leather_tex)
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
	_hair.rim_enabled = true
	_hair.rim = 0.18
	_hair.rim_tint = 0.55
	_hair.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hair.set_meta("mara_surface_profile", "hair")

	_sclera = StandardMaterial3D.new()
	_sclera.albedo_color = Color(0.93, 0.93, 0.91)
	_sclera.roughness = 0.32

	_iris = StandardMaterial3D.new()
	_iris.albedo_color = eye_color
	_iris.roughness = 0.1
	_iris.metallic = 0.0
	# A clearcoat layer fakes the wet, glossy cornea over the iris — the catchlight
	# it produces is one of the strongest "this is alive" cues on a face.
	_iris.clearcoat_enabled = true
	_iris.clearcoat = 1.0
	_iris.clearcoat_roughness = 0.03
	_sclera.clearcoat_enabled = true
	_sclera.clearcoat = 0.8
	_sclera.clearcoat_roughness = 0.05

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
		# A tiny bright catchlight sphere at the upper edge of the eye — the spark
		# of a reflected light source that reads instantly as a living eye.
		var catchlight := _sphere(0.0035, _catchlight_material())
		catchlight.position = Vector3(0.05 * side, -0.008, -0.118)
		head.add_child(catchlight)
		var brow := _sphere(0.022, _hair)
		brow.position = Vector3(0.046 * side, 0.012, -0.098)
		brow.scale = Vector3(1.1, 0.28, 0.5)
		head.add_child(brow)
		var eyelid := _box("MaraBlinkLid", Vector3(0.052, 0.006, 0.007), _skin)
		eyelid.position = Vector3(0.046 * side, -0.013, -0.123)
		eyelid.scale.y = 0.01
		head.add_child(eyelid)
		_eyelids.append(eyelid)

	var nose := _sphere(0.02, _skin)
	nose.position = Vector3(0.0, -0.052, -0.1)
	nose.scale = Vector3(0.8, 1.45, 1.55)
	head.add_child(nose)

	var mouth := _sphere(0.016, _mouth)
	mouth.position = Vector3(0.0, -0.09, -0.092)
	mouth.scale = Vector3(1.9, 0.5, 0.55)
	head.add_child(mouth)

	# Ears: flattened skin ovals on each side of the head, set slightly back.
	for ear_side: float in [-1.0, 1.0]:
		var ear := _sphere(0.034, _skin)
		ear.position = Vector3(0.118 * ear_side, -0.01, 0.016)
		ear.scale = Vector3(0.42, 1.05, 0.72)
		head.add_child(ear)


func _update_blink(delta: float) -> void:
	if _eyelids.is_empty():
		return
	_blink_t = fposmod(_blink_t + delta, BLINK_INTERVAL)
	var openness := 0.0
	if _blink_t < BLINK_DURATION:
		openness = sin((_blink_t / BLINK_DURATION) * PI)
	for lid in _eyelids:
		if lid != null:
			lid.scale.y = lerpf(0.01, 1.0, openness)


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

	var strap := _rounded_bar("MaraMessengerStrap", 0.78, 0.03, 0.015, _strap)
	strap.position = Vector3(-0.04, 0.42, -0.17)
	strap.rotation.z = -0.42
	hips.add_child(strap)
	_track_mara_soft_part(strap, 0.38, 0.22, 0.5)

	var pendant_chain := _rounded_bar("MaraPendantCord", 0.15, 0.007, 0.007, _strap)
	pendant_chain.position = Vector3(0.0, 0.47, -0.18)
	hips.add_child(pendant_chain)
	_track_mara_soft_part(pendant_chain, 0.7, 0.35, 0.65)

	var pendant := _sphere(0.025, _metal)
	pendant.name = "MaraPendant"
	pendant.position = Vector3(0.0, 0.39, -0.185)
	pendant.scale = Vector3(0.8, 1.1, 0.25)
	hips.add_child(pendant)
	_track_mara_soft_part(pendant, 0.85, 0.48, 0.75)

	_add_cargo_pocket(rig, "Hips/HipL", 1.0)
	_add_cargo_pocket(rig, "Hips/HipR", -1.0)
	_add_mara_boot_detail(rig, "Hips/HipL", 1.0)
	_add_mara_boot_detail(rig, "Hips/HipR", -1.0)
	_add_mara_jacket_trim(hips)
	_add_mara_rear_details(hips)
	_add_mara_full_body_gear(rig, hips)
	_add_mara_head_details(rig)
	_disable_mara_cosmetic_shadows(hips)


func _add_imported_mara_mesh(rig: Node) -> void:
	if imported_mara_scene == null:
		return
	var hips := rig.get_node_or_null("Hips") as Node3D
	if hips == null:
		return
	var visual := imported_mara_scene.instantiate() as Node3D
	if visual == null:
		return
	visual.name = "MaraImportedMesh"
	visual.position = imported_mara_offset
	visual.scale = Vector3.ONE * imported_mara_scale
	_imported_visual = visual
	_prepare_imported_visual(visual)
	hips.add_child.call_deferred(visual)
	if hide_procedural_when_imported:
		_set_procedural_visible.call_deferred(rig, false)


func _disable_mara_cosmetic_shadows(node: Node) -> void:
	if node is MeshInstance3D and node.name.begins_with("Mara"):
		var mi := node as MeshInstance3D
		if node.name != "MaraCroppedJacket":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.set_meta("mara_cosmetic_shadow_disabled", true)
			_mara_cosmetics.append(mi)
	for child in node.get_children():
		_disable_mara_cosmetic_shadows(child)


func _update_mara_cosmetic_lod() -> void:
	if _mara_cosmetics.is_empty() or _rig == null or not _procedural_visible:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		_set_mara_cosmetics_visible(true)
		return
	var hips := _rig.get_node_or_null("Hips") as Node3D
	if hips == null:
		return
	var visible := true
	if cosmetic_lod_distance > 0.0:
		visible = camera.global_position.distance_to(hips.global_position) <= cosmetic_lod_distance
	_set_mara_cosmetics_visible(visible)


func _set_mara_cosmetics_visible(visible: bool) -> void:
	for mesh in _mara_cosmetics:
		if mesh != null:
			mesh.visible = visible


func _track_mara_soft_part(node: Node3D, sway: float, bob: float, twist: float) -> void:
	node.set_meta("mara_soft_motion", true)
	(
		_mara_soft_parts
		. append(
			{
				"node": node,
				"rest_position": node.position,
				"rest_rotation": node.rotation,
				"sway": sway,
				"bob": bob,
				"twist": twist,
			}
		)
	)


func _update_mara_soft_motion(delta: float) -> void:
	if _mara_soft_parts.is_empty() or _rig == null or not _procedural_visible:
		return
	var hips := _rig.get_node_or_null("Hips") as Node3D
	var torso := _rig.get_node_or_null("Hips/Torso") as Node3D
	if hips == null:
		return
	var torso_twist := 0.0
	if torso != null:
		torso_twist = torso.rotation.y
	var weight := clampf(MARA_SOFT_MOTION_RATE * delta, 0.0, 1.0)
	var pulse := sin(_breath_t * 7.0) * 0.012
	for part in _mara_soft_parts:
		var node := part["node"] as Node3D
		if node == null:
			continue
		var rest_position := part["rest_position"] as Vector3
		var rest_rotation := part["rest_rotation"] as Vector3
		var sway := float(part["sway"])
		var bob := float(part["bob"])
		var twist := float(part["twist"])
		var target_position := (
			rest_position
			+ Vector3(-hips.position.x * sway, absf(hips.position.x) * bob + pulse * bob, 0.0)
		)
		var target_rotation := (
			rest_rotation
			+ Vector3(
				hips.rotation.z * 0.35 * sway,
				-torso_twist * twist,
				-hips.position.x * 1.6 * sway + pulse
			)
		)
		node.position = node.position.lerp(target_position, weight)
		node.rotation = node.rotation.lerp(target_rotation, weight)


func _update_imported_mara_visibility() -> void:
	if _imported_visual == null or _rig == null:
		return
	var show_imported := _should_show_imported_mara()
	var procedural_target := not show_imported
	if show_imported == _show_imported_mara and _procedural_visible == procedural_target:
		return
	_show_imported_mara = show_imported
	_set_imported_visual_active(show_imported)
	_set_procedural_visible(_rig, procedural_target)


func _should_show_imported_mara() -> bool:
	if not switch_imported_mara_by_camera:
		return hide_procedural_when_imported
	var camera := get_viewport().get_camera_3d()
	if camera == null or _rig == null:
		return hide_procedural_when_imported
	var hips := _rig.get_node_or_null("Hips") as Node3D
	if hips == null:
		return hide_procedural_when_imported
	var to_camera := camera.global_position - hips.global_position
	if to_camera.length_squared() <= 0.0001:
		return hide_procedural_when_imported
	var front := -hips.global_transform.basis.z.normalized()
	var camera_dot := front.dot(to_camera.normalized())
	if _show_imported_mara:
		return camera_dot >= imported_mara_rear_dot
	return camera_dot >= imported_mara_front_dot


func _prepare_imported_visual(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	for child in node.get_children():
		_prepare_imported_visual(child)


func _set_imported_visual_active(active: bool) -> void:
	if _imported_visual == null:
		return
	_imported_visual.visible = active
	_set_imported_meshes_active(_imported_visual, active)


func _set_imported_meshes_active(node: Node, active: bool) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if active
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
	for child in node.get_children():
		_set_imported_meshes_active(child, active)


func _set_procedural_visible(rig: Node, visible: bool) -> void:
	if _procedural_visible == visible:
		return
	_procedural_visible = visible
	var hips := rig.get_node_or_null("Hips")
	if hips != null:
		_set_meshes_visible(hips, visible)


func _set_meshes_visible(node: Node, visible: bool) -> void:
	if node.name == "MaraImportedMesh":
		return
	if node.get_meta("humanoid_body_replaced", false):
		return
	if node is MeshInstance3D:
		(node as MeshInstance3D).visible = visible
	for child in node.get_children():
		_set_meshes_visible(child, visible)


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


func _add_mara_boot_detail(rig: Node, hip_path: String, side: float) -> void:
	var hip: Node3D = rig.get_node_or_null(hip_path) as Node3D
	if hip == null:
		return
	var boot_cuff := _box("MaraBootCuff", Vector3(0.14, 0.052, 0.13), _strap)
	boot_cuff.position = Vector3(0.0, -0.77, 0.02)
	hip.add_child(boot_cuff)
	var side_zip := _box("MaraBootSideZip", Vector3(0.01, 0.16, 0.012), _metal)
	side_zip.position = Vector3(0.065 * side, -0.81, -0.018)
	hip.add_child(side_zip)


func _add_mara_jacket_trim(hips: Node3D) -> void:
	var collar_l := _box("MaraJacketCollarL", Vector3(0.065, 0.18, 0.022), _jacket)
	collar_l.position = Vector3(0.065, 0.66, -0.158)
	collar_l.rotation.z = 0.55
	hips.add_child(collar_l)
	var collar_r := _box("MaraJacketCollarR", Vector3(0.065, 0.18, 0.022), _jacket)
	collar_r.position = Vector3(-0.065, 0.66, -0.158)
	collar_r.rotation.z = -0.55
	hips.add_child(collar_r)
	var zipper := _box("MaraJacketZipper", Vector3(0.012, 0.42, 0.012), _metal)
	zipper.position = Vector3(-0.018, 0.43, -0.178)
	hips.add_child(zipper)
	var pouch := _box("MaraUtilityPouch", Vector3(0.13, 0.12, 0.065), _strap)
	pouch.position = Vector3(0.22, 0.0, -0.02)
	pouch.rotation.z = -0.08
	hips.add_child(pouch)


func _add_mara_rear_details(hips: Node3D) -> void:
	var back_yoke := _box("MaraJacketBackYoke", Vector3(0.34, 0.038, 0.018), _jacket)
	back_yoke.position = Vector3(0.0, 0.61, 0.145)
	hips.add_child(back_yoke)
	for side: float in [-1.0, 1.0]:
		var seam := _box("MaraRearJacketSeam", Vector3(0.018, 0.28, 0.014), _jacket)
		seam.position = Vector3(0.12 * side, 0.43, 0.155)
		seam.rotation.z = -0.05 * side
		hips.add_child(seam)
	var rear_waist := _box("MaraRearWaistTab", Vector3(0.22, 0.03, 0.022), _strap)
	rear_waist.position = Vector3(0.0, 0.215, 0.16)
	hips.add_child(rear_waist)
	var strap_back := _rounded_bar("MaraMessengerStrapBack", 0.82, 0.022, 0.013, _strap)
	strap_back.position = Vector3(0.04, 0.42, 0.175)
	strap_back.rotation.z = 0.38
	hips.add_child(strap_back)
	_track_mara_soft_part(strap_back, 0.32, 0.18, 0.45)
	for side: float in [-1.0, 1.0]:
		var shoulder_tab := _box("MaraShoulderTab", Vector3(0.12, 0.025, 0.038), _strap)
		shoulder_tab.position = Vector3(0.22 * side, 0.61, 0.08)
		shoulder_tab.rotation.z = -0.12 * side
		hips.add_child(shoulder_tab)


func _add_mara_full_body_gear(rig: Node, hips: Node3D) -> void:
	var holster := _box("MaraSideHolster", Vector3(0.062, 0.18, 0.042), _strap)
	holster.position = Vector3(0.215, -0.12, -0.025)
	holster.rotation.z = -0.12
	hips.add_child(holster)

	for side: float in [-1.0, 1.0]:
		var hip := rig.get_node_or_null("Hips/Hip%s" % ("L" if side > 0.0 else "R")) as Node3D
		if hip == null:
			continue
		var thigh_band := _box("MaraThighUtilityBand", Vector3(0.15, 0.032, 0.13), _strap)
		thigh_band.position = Vector3(0.0, -0.17, -0.005)
		hip.add_child(thigh_band)

		var knee_pad := _box("MaraKneePad", Vector3(0.108, 0.068, 0.02), _jacket)
		knee_pad.position = Vector3(0.0, -0.405, -0.062)
		knee_pad.rotation.x = 0.08
		hip.add_child(knee_pad)

		var ankle := hip.get_node_or_null("Knee/Ankle") as Node3D
		if ankle != null:
			var boot_sole := _box("MaraBootSole", Vector3(0.11, 0.018, 0.16), _glove)
			boot_sole.position = Vector3(0.0, -0.018, 0.045)
			ankle.add_child(boot_sole)

	for side: float in [-1.0, 1.0]:
		var elbow := (
			rig.get_node_or_null("Hips/Shoulder%s/Elbow" % ("L" if side > 0.0 else "R")) as Node3D
		)
		if elbow == null:
			continue
		var wrist_wrap := _box("MaraWristWrap", Vector3(0.094, 0.032, 0.078), _strap)
		wrist_wrap.position = Vector3(0.0, -0.255, 0.0)
		elbow.add_child(wrist_wrap)
		var knuckles := _box("MaraGloveKnuckles", Vector3(0.08, 0.014, 0.018), _metal)
		knuckles.position = Vector3(0.0, -0.325, -0.042)
		elbow.add_child(knuckles)


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

	var earring := _sphere(0.012, _metal)
	earring.name = "MaraBrassEarring"
	earring.position = Vector3(-0.127, -0.035, 0.01)
	earring.scale = Vector3(0.6, 1.0, 0.6)
	head.add_child(earring)

	var rear_hair := _sphere(0.075, _hair)
	rear_hair.name = "MaraRearHairMass"
	rear_hair.position = Vector3(0.0, 0.02, 0.075)
	rear_hair.scale = Vector3(1.25, 1.45, 0.72)
	head.add_child(rear_hair)
	_track_mara_soft_part(rear_hair, 0.24, 0.2, 0.42)

	var rear_streak := _sphere(0.018, _silver_hair)
	rear_streak.name = "MaraRearSilverStreak"
	rear_streak.position = Vector3(-0.045, 0.018, 0.12)
	rear_streak.rotation.z = -0.22
	rear_streak.scale = Vector3(0.55, 1.9, 0.35)
	head.add_child(rear_streak)

	for side: float in [-1.0, 1.0]:
		var side_lock := _sphere(0.044, _hair)
		side_lock.name = "MaraSideHairLock"
		side_lock.position = Vector3(0.092 * side, -0.055, -0.02)
		side_lock.rotation.z = -0.16 * side
		side_lock.scale = Vector3(0.42, 1.8, 0.5)
		head.add_child(side_lock)
		_track_mara_soft_part(side_lock, 0.6 * side, 0.26, 0.55)


func _catchlight_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 1.0, 1.0)
	mat.emission_energy_multiplier = 2.0
	return mat


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
	var upper_arm_mat: Material = _jacket if use_mara_hero_profile else _shirt
	shoulder.add_child(
		_seg(
			HumanoidMesh.limb(0.36, 0.062, 0.062, 0.05, 12, 14),
			upper_arm_mat,
			Vector3(0, -0.165, 0)
		)
	)
	var elbow := Node3D.new()
	elbow.name = "Elbow"
	elbow.position = Vector3(0, -0.33, 0)
	shoulder.add_child(elbow)
	elbow.add_child(
		_seg(HumanoidMesh.limb(0.34, 0.05, 0.048, 0.04, 12, 14), _skin, Vector3(0, -0.155, 0))
	)
	if use_mara_hero_profile:
		elbow.add_child(
			_seg(
				HumanoidMesh.limb(0.25, 0.053, 0.051, 0.043, 12, 12), _shirt, Vector3(0, -0.105, 0)
			)
		)
		var cuff := _box("MaraSleeveCuff", Vector3(0.115, 0.035, 0.105), _jacket)
		cuff.position = Vector3(0.0, -0.02, 0.0)
		elbow.add_child(cuff)
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


func _rounded_bar(
	node_name: String, length: float, half_width: float, half_depth: float, mat: Material
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var rings: Array = [
		Vector3(length * 0.5, half_width * 0.82, half_depth * 0.82),
		Vector3(length * 0.42, half_width, half_depth),
		Vector3(0.0, half_width, half_depth),
		Vector3(-length * 0.42, half_width, half_depth),
		Vector3(-length * 0.5, half_width * 0.82, half_depth * 0.82),
	]
	mi.name = node_name
	mi.mesh = HumanoidMesh.to_mesh(HumanoidMesh.lofted(rings, 12))
	mi.material_override = mat
	return mi


func _hide(rig: Node, path: String) -> void:
	var node: MeshInstance3D = rig.get_node_or_null(path) as MeshInstance3D
	if node != null:
		node.set_meta("humanoid_body_replaced", true)
		node.visible = false


func _rig_float(rig: Node, prop: String, fallback: float) -> float:
	var v: Variant = rig.get(prop)
	return float(v) if v != null else fallback


func _fabric(
	color: Color,
	roughness: float,
	rim: float,
	albedo_tex: Texture2D = null,
	use_procedural_albedo: bool = true
) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = 0.0
	mat.rim_enabled = rim > 0.0
	mat.rim = rim
	mat.rim_tint = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.set_meta("mara_surface_profile", "fabric")
	_apply_detail_normal(mat, HumanoidTextures.fabric_normal(), 0.6, 11.0)
	if albedo_tex != null:
		# Photoreal cloth (denim/cotton from Codex image gen, docs/ASSETS.md),
		# tiled larger than the procedural weave so the real fabric reads at scale.
		mat.albedo_texture = albedo_tex
		mat.uv1_scale = Vector3(4.0, 4.0, 4.0)
	elif use_procedural_albedo:
		mat.albedo_texture = HumanoidTextures.fabric_albedo()
	return mat


func _leather(color: Color, roughness: float, albedo_tex: Texture2D = null) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = 0.0
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.36
	mat.clearcoat_roughness = 0.24
	mat.rim_enabled = true
	mat.rim = 0.12
	mat.rim_tint = 0.45
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.set_meta("mara_surface_profile", "leather")
	_apply_detail_normal(mat, HumanoidTextures.fabric_normal(), 0.3, 18.0)
	if albedo_tex != null:
		mat.albedo_texture = albedo_tex
		mat.uv1_scale = Vector3(5.0, 5.0, 5.0)
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
	mat.set_meta("mara_detail_normal_strength", strength)
	mat.set_meta("mara_detail_normal_scale", scale)
