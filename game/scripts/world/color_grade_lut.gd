class_name ColorGradeLut
extends RefCounted
## Builds a 3D color-correction LUT for the WorldEnvironment's adjustment stage.
##
## The grade is a tasteful "Vice City" filmic split-tone applied after
## tonemapping: shadows drift toward teal/cyan, highlights warm toward sunset
## orange, with a gentle S-curve and a touch of saturation. This is what gives
## the open world a cohesive neon-noir palette instead of a neutral render.
##
## `grade()` is the pure per-color transform (unit-tested); `build()` bakes it
## into an ImageTexture3D suitable for Environment.adjustment_color_correction.

const DEFAULT_SIZE: int = 17
const DEFAULT_STRENGTH: float = 1.0
const _LUMA := Vector3(0.2126, 0.7152, 0.0722)


## Grade a single display-referred color (channels in [0, 1]). `strength` scales
## the whole effect so callers can dial it back to taste (0 = identity).
static func grade(src: Color, strength: float = DEFAULT_STRENGTH) -> Color:
	var r := src.r
	var g := src.g
	var b := src.b
	var luma := r * _LUMA.x + g * _LUMA.y + b * _LUMA.z
	# Weights that isolate the shadow and highlight ends of the tonal range.
	var shadow_w := clampf(1.0 - luma * 1.6, 0.0, 1.0)
	var high_w := clampf((luma - 0.5) * 2.0, 0.0, 1.0)
	# Split-tone: cool the shadows, warm the highlights.
	r += (-0.010 * shadow_w + 0.100 * high_w) * strength
	g += (0.050 * shadow_w + 0.030 * high_w) * strength
	b += (0.100 * shadow_w - 0.070 * high_w) * strength
	# Gentle S-curve pivoting on mid-grey for a filmic contrast lift.
	r += (r - 0.5) * 0.08 * strength
	g += (g - 0.5) * 0.08 * strength
	b += (b - 0.5) * 0.08 * strength
	# Modest saturation bump around the new luma.
	var luma2 := r * _LUMA.x + g * _LUMA.y + b * _LUMA.z
	var sat := 1.0 + 0.10 * strength
	r = luma2 + (r - luma2) * sat
	g = luma2 + (g - luma2) * sat
	b = luma2 + (b - luma2) * sat
	return Color(clampf(r, 0.0, 1.0), clampf(g, 0.0, 1.0), clampf(b, 0.0, 1.0), 1.0)


## Bake the grade into a `size^3` ImageTexture3D. Slice z maps to the blue axis;
## within each slice x is red and y is green, matching Godot's LUT sampling.
static func build(size: int = DEFAULT_SIZE, strength: float = DEFAULT_STRENGTH) -> ImageTexture3D:
	size = maxi(size, 2)
	var denom := float(size - 1)
	var slices: Array[Image] = []
	for z in size:
		var img := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
		for y in size:
			for x in size:
				var graded := grade(Color(x / denom, y / denom, z / denom, 1.0), strength)
				img.set_pixel(x, y, graded)
		slices.append(img)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, size, size, size, false, slices)
	return tex
