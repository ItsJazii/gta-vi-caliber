class_name PbrMaterial
extends RefCounted
## Turns an AI-generated (or hand-authored) PBR texture set into a game-ready
## StandardMaterial3D with the channels wired correctly — the glue between
## "unlimited generated images" and "renders right in-engine". This is the
## drop-in pipeline a contributor or agent uses after a GPT-image → texture-set
## step: put the maps in a folder and call from_set(); no per-material hand-config.
##
## Convention — a material lives in `assets/materials/<name>/` with any of:
##   albedo.png  normal.png  roughness.png  metallic.png  ao.png  emission.png
## Missing maps are simply skipped (a set with only albedo+normal still works).
##
## Provenance still applies (docs/ASSETS.md): generated maps must be original —
## not prompted to imitate a copyrighted work — and ledgered in the same PR.

## Map key → expected filename inside the material folder.
const MAP_FILES := {
	"albedo": "albedo.png",
	"normal": "normal.png",
	"roughness": "roughness.png",
	"metallic": "metallic.png",
	"ao": "ao.png",
	"emission": "emission.png",
}


## Pure decision step (headless-testable): given which map keys are present,
## return the StandardMaterial3D feature flags that should be enabled. Kept
## separate from file IO so the wiring logic is unit-tested without textures.
static func channel_flags(present: PackedStringArray) -> Dictionary:
	return {
		"has_albedo": "albedo" in present,
		"normal_enabled": "normal" in present,
		"roughness_textured": "roughness" in present,
		"metallic_textured": "metallic" in present,
		"ao_enabled": "ao" in present,
		"emission_enabled": "emission" in present,
	}


## Build a StandardMaterial3D from the texture set in `dir`. Always returns a
## valid material — an empty/partial folder just yields fewer wired channels.
## `triplanar` is for large surfaces (ground, terrain) where UV seams would show.
static func from_set(
	dir: String, triplanar: bool = false, uv_scale: float = 1.0
) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var present := PackedStringArray()
	for key in MAP_FILES:
		var path := dir.path_join(MAP_FILES[key])
		if ResourceLoader.exists(path):
			present.append(key)
			_apply_map(mat, key, load(path) as Texture2D)

	var flags := channel_flags(present)
	if flags["normal_enabled"]:
		mat.normal_enabled = true
	if flags["ao_enabled"]:
		mat.ao_enabled = true
	if flags["emission_enabled"]:
		mat.emission_enabled = true
	# When a data map drives a channel, the scalar must be 1.0 so the texture is
	# used at full value (StandardMaterial3D multiplies scalar × texture).
	if flags["roughness_textured"]:
		mat.roughness = 1.0
	if flags["metallic_textured"]:
		mat.metallic = 1.0

	if triplanar:
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	return mat


## Assign one texture to its channel, picking the right slot and (for grayscale
## data maps) the red channel that single-channel exports land in.
static func _apply_map(mat: StandardMaterial3D, key: String, tex: Texture2D) -> void:
	match key:
		"albedo":
			mat.albedo_texture = tex
		"normal":
			mat.normal_texture = tex
		"roughness":
			mat.roughness_texture = tex
			mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		"metallic":
			mat.metallic_texture = tex
			mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		"ao":
			mat.ao_texture = tex
			mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		"emission":
			mat.emission_texture = tex
