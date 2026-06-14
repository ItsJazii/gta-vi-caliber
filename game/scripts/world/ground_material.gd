class_name GroundMaterial
extends RefCounted
## Procedural ground material for district tiles. Shaded (so the ground breathes
## with the day/night cycle, the dusk grade and the streetlamps instead of
## rendering as a flat black slab the lighting cannot touch) and mottled by a
## triplanar noise ramp between two dark tarmac tones, so a large flat tile reads
## as worn asphalt rather than one dead colour. No texture assets: the noise is
## generated procedurally. Built once per district tile in DistrictLoader.

## Two dark tones the noise mixes between; kept low so the night city stays moody
## but the ground still catches warm light where lamps and the dusk sun fall.
const TONE_LOW := Color(0.06, 0.065, 0.07)
const TONE_HIGH := Color(0.12, 0.12, 0.13)


static func build() -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.015

	var ramp := Gradient.new()
	ramp.set_color(0, TONE_LOW)
	ramp.set_color(1, TONE_HIGH)

	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.color_ramp = ramp
	tex.width = 256
	tex.height = 256
	tex.seamless = true

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	# Triplanar so the tile needs no UVs and the mottling wraps its top face at a
	# few-metres scale; matte so it reads as asphalt, not plastic.
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.06, 0.06, 0.06)
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
