class_name SkyModel
extends RefCounted
## Pure, scene-free day/night model — the single source of truth for where the
## sun is and what the world's key light, ambient and sky should look like at a
## given time of day. SkyController reads these values every frame to drive the
## DirectionalLight, the WorldEnvironment and the sky shader (sky.gdshader), so
## the atmosphere, the cast shadows and the ambient term always agree.
##
## Everything is a deterministic function of `tod` (time of day, hours in
## [0, 24)), which keeps it unit-testable headless. No Godot nodes, no globals.
## Covered by tests/unit/test_sky_model.gd.

## Hours of a full day. `tod` wraps on this.
const DAY_HOURS: float = 24.0

## How far the sun's arc leans toward the south (+ = further south). 0 puts the
## noon sun straight overhead; a small lean reads as a more natural mid-latitude
## arc. Affects the horizontal plane only.
const SOUTH_LEAN: float = 0.35

## Peak daylight energy for the DirectionalLight at the sun's highest point.
const MAX_SUN_ENERGY: float = 1.35

## Residual key-light energy at night (moonlight). Never fully black so shadowed
## night scenes still read.
const MOON_ENERGY: float = 0.06

## Cool key energy for a dedicated moon DirectionalLight at full night (scaled by
## night_amount and weather). Brighter than the sun's MOON_ENERGY floor so a
## moonlit night reads with a soft cool key and real shadows, not pitch black.
const MOON_LIGHT_ENERGY: float = 0.2

## Daytime ambient light energy at the sun's zenith.
const MAX_AMBIENT: float = 0.55

## Ambient floor at deep night.
const MIN_AMBIENT: float = 0.04

## Twilight thresholds expressed as sun height (sin of elevation), so the ramps
## track real dusk/dawn rather than snapping at the geometric horizon:
##   sin(0°)=0 horizon · sin(-6°)≈-0.10 civil · sin(-12°)≈-0.21 nautical ·
##   sin(-18°)≈-0.31 astronomical (full dark).
## DAWN_* drives the key light (fades out a touch below the horizon); NIGHT_*
## drives the long star/sky-tint ramp; SKY_* keeps the atmosphere glowing
## through twilight so the afterglow reddens instead of cutting to black.
const DAWN_LOW: float = -0.10
const DAWN_HIGH: float = 0.10
const NIGHT_LOW: float = -0.31
const NIGHT_HIGH: float = 0.04
const SKY_LOW: float = -0.28
const SKY_HIGH: float = 0.06

## Key-light colour high in the sky (slightly warm white) and at the horizon
## (sunrise/sunset orange) — lerped by how warm the low sun is.
const DAY_LIGHT_COLOR: Color = Color(1.0, 0.98, 0.95)
const HORIZON_LIGHT_COLOR: Color = Color(1.0, 0.54, 0.26)

## Ambient (sky fill) tint — warm sun-bleached daylight easing to a cool moonlit
## blue at night, so night shadows read cool instead of keeping the warm daytime
## colour the scene authored.
const DAY_AMBIENT_COLOR: Color = Color(0.92, 0.76, 0.62)
const NIGHT_AMBIENT_COLOR: Color = Color(0.34, 0.42, 0.66)


## Unit vector pointing from the world TO the sun at time `tod`.
## +X is east, +Y is up, -Z is north (Godot's forward), so the sun rises in the
## east, climbs through the southern sky and sets in the west.
static func sun_direction(tod: float) -> Vector3:
	var a := _solar_angle(tod)
	# cos(a): +1 at noon, 0 at 06:00/18:00, -1 at midnight -> vertical sweep.
	# -sin(a): +1 east at sunrise, -1 west at sunset -> east-west sweep.
	var dir := Vector3(-sin(a), cos(a), -SOUTH_LEAN)
	return dir.normalized()


## Sun elevation above the horizon in radians (negative when set).
static func sun_elevation(tod: float) -> float:
	return asin(clampf(sun_direction(tod).y, -1.0, 1.0))


## Roughly antipodal moon direction — opposite the sun so it rides high at
## night. Unit vector pointing TO the moon.
static func moon_direction(tod: float) -> Vector3:
	return -sun_direction(tod)


## 0 in full daylight .. 1 in deep night, smooth across twilight. Drives star
## visibility and the night sky tint.
static func night_amount(tod: float) -> float:
	var h := sun_direction(tod).y
	return 1.0 - smoothstep(NIGHT_LOW, NIGHT_HIGH, h)


## DirectionalLight energy: ramps from moonlight up to full daylight with sun
## height. Never below MOON_ENERGY.
static func light_energy(tod: float) -> float:
	var h := sun_direction(tod).y
	var day := smoothstep(DAWN_LOW, DAWN_HIGH, h)
	return lerpf(MOON_ENERGY, MAX_SUN_ENERGY, day)


## Key-light colour — warm orange when the sun is low, neutral when high.
static func light_color(tod: float) -> Color:
	var h := sun_direction(tod).y
	var warmth := 1.0 - smoothstep(0.0, 0.4, h)
	return HORIZON_LIGHT_COLOR.lerp(DAY_LIGHT_COLOR, 1.0 - warmth)


## Ambient (sky-contributed) light energy for the WorldEnvironment.
static func ambient_energy(tod: float) -> float:
	var h := sun_direction(tod).y
	var day := smoothstep(DAWN_LOW, DAWN_HIGH, h)
	return lerpf(MIN_AMBIENT, MAX_AMBIENT, day)


## Ambient (sky fill) colour for the WorldEnvironment — warm by day, cool by
## night, crossing over through twilight on the same ramp as the key light.
static func ambient_color(tod: float) -> Color:
	var h := sun_direction(tod).y
	var day := smoothstep(DAWN_LOW, DAWN_HIGH, h)
	return NIGHT_AMBIENT_COLOR.lerp(DAY_AMBIENT_COLOR, day)


## Overall daylight scale fed to the sky shader's `sun_energy`. Tracks the key
## light but clamped to [0,1] so the shader's HDR atmosphere stays in range.
static func sky_sun_energy(tod: float) -> float:
	var h := sun_direction(tod).y
	return smoothstep(SKY_LOW, SKY_HIGH, h)


## True while any part of the solar disk is above the horizon (used to toggle
## cast shadows — pointless at night).
static func is_sun_up(tod: float) -> bool:
	return sun_direction(tod).y > -0.02


## Solar hour-angle in radians, 0 at solar noon (12:00). Wraps `tod` into a day.
static func _solar_angle(tod: float) -> float:
	var t := fposmod(tod, DAY_HOURS)
	return (t - 12.0) / DAY_HOURS * TAU
