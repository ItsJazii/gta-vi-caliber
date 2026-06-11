class_name DaylightMath
extends RefCounted
## Pure, scene-free time-of-day model: hour of day [0, 24) → sun angles, key
## light energy/colour, sky colour ramp (night → golden dawn → noon → golden
## dusk → night), window-glow amount, and streetlight on/off with hysteresis.
## TimeOfDay reads these every frame to drive the scene; nothing here touches
## nodes or globals so it unit-tests headless (tests/unit/test_daylight_math.gd).
##
## Conventions: elevation in degrees above the horizon (negative = set);
## azimuth in degrees clockwise from north (-Z), so 90 = east (+X),
## 180 = south (+Z), 270 = west (-X). Summer-coast day: sun rises 06:00,
## peaks at solar noon 13:00, sets 20:00 — long golden evenings.

const SUNRISE_HOUR: float = 6.0
const SUNSET_HOUR: float = 20.0

## Sun elevation at solar noon. ~60° reads as a sun-soaked low latitude summer.
const NOON_ELEVATION_DEG: float = 60.0

## How far below the horizon the sun dips at the middle of the night.
const NIGHT_DEPTH_DEG: float = 45.0

## Key-light (DirectionalLight) energy at full midday.
const MAX_SUN_ENERGY: float = 1.3

## Residual key-light energy at night (moonlight) so the city never goes black.
const NIGHT_ENERGY: float = 0.05

## Streetlights/windows switch ON when the sun drops below this elevation...
const LIGHTS_ON_BELOW_DEG: float = 1.0
## ...and switch OFF only once it climbs back above this one (hysteresis band
## so lights never flicker around the threshold).
const LIGHTS_OFF_ABOVE_DEG: float = 5.0

## Key-light colour ramp endpoints.
const NIGHT_LIGHT_COLOR: Color = Color(0.55, 0.62, 0.78)
const GOLDEN_LIGHT_COLOR: Color = Color(1.0, 0.6, 0.3)
const DAY_LIGHT_COLOR: Color = Color(1.0, 0.97, 0.92)

## Sky colour ramp endpoints (zenith and horizon).
const NIGHT_SKY_TOP: Color = Color(0.01, 0.02, 0.06)
const DAY_SKY_TOP: Color = Color(0.22, 0.44, 0.78)
const NIGHT_HORIZON: Color = Color(0.05, 0.06, 0.13)
const DAY_HORIZON: Color = Color(0.6, 0.74, 0.86)
const GOLDEN_HORIZON: Color = Color(1.0, 0.44, 0.36)


## Sun elevation above the horizon in degrees at `hour`. Two sinusoidal arcs:
## 0° at sunrise/sunset, peak at solar noon, dipping to -NIGHT_DEPTH_DEG at the
## middle of the night.
static func sun_elevation_deg(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	var day_len := SUNSET_HOUR - SUNRISE_HOUR
	if h >= SUNRISE_HOUR and h <= SUNSET_HOUR:
		return NOON_ELEVATION_DEG * sin(PI * (h - SUNRISE_HOUR) / day_len)
	var since_sunset := fposmod(h - SUNSET_HOUR, 24.0)
	return -NIGHT_DEPTH_DEG * sin(PI * since_sunset / (24.0 - day_len))


## Sun azimuth in degrees clockwise from north: east (90°) at sunrise, south
## (180°) at solar noon, west (270°) at sunset, sweeping on through north
## overnight so the arc never reverses.
static func sun_azimuth_deg(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	var day_len := SUNSET_HOUR - SUNRISE_HOUR
	if h >= SUNRISE_HOUR and h <= SUNSET_HOUR:
		return 90.0 + 180.0 * (h - SUNRISE_HOUR) / day_len
	var since_sunset := fposmod(h - SUNSET_HOUR, 24.0)
	return fposmod(270.0 + 180.0 * since_sunset / (24.0 - day_len), 360.0)


## Unit vector pointing from the world TO the sun (may dip below the horizon).
static func sun_direction(hour: float) -> Vector3:
	var el := deg_to_rad(sun_elevation_deg(hour))
	var az := deg_to_rad(sun_azimuth_deg(hour))
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))


## Direction TO whichever body keys the scene: the sun while it is up, else an
## antipodal "moon" so the night key light still comes from above.
static func key_light_direction(hour: float) -> Vector3:
	var sun := sun_direction(hour)
	return sun if sun.y >= 0.0 else -sun


## 0 in deep night → 1 in full daylight, smooth across civil twilight.
static func day_factor(hour: float) -> float:
	return smoothstep(-6.0, 8.0, sun_elevation_deg(hour))


## 1 only while the sun sits in the low golden band around the horizon
## (dawn/dusk); 0 at night and at midday. Drives the warm colour push.
static func golden_factor(hour: float) -> float:
	var el := sun_elevation_deg(hour)
	return smoothstep(-6.0, 0.0, el) * (1.0 - smoothstep(10.0, 25.0, el))


## Key-light energy: moonlight floor at night up to full sun at midday.
static func sun_energy(hour: float) -> float:
	var lift := smoothstep(-2.0, 12.0, sun_elevation_deg(hour))
	return lerpf(NIGHT_ENERGY, MAX_SUN_ENERGY, lift)


## Key-light colour: cool dim moonlight → golden horizon sun → warm white noon.
static func sun_color(hour: float) -> Color:
	var base := NIGHT_LIGHT_COLOR.lerp(DAY_LIGHT_COLOR, day_factor(hour))
	return base.lerp(GOLDEN_LIGHT_COLOR, golden_factor(hour))


## Sky zenith colour for ProceduralSkyMaterial.sky_top_color.
static func sky_top_color(hour: float) -> Color:
	return NIGHT_SKY_TOP.lerp(DAY_SKY_TOP, day_factor(hour))


## Sky horizon colour — warm-saturated through the golden band.
static func sky_horizon_color(hour: float) -> Color:
	var base := NIGHT_HORIZON.lerp(DAY_HORIZON, day_factor(hour))
	return base.lerp(GOLDEN_HORIZON, golden_factor(hour))


## Distance-fog colour: tracks the key light but fades to near-black at night
## so fog never washes the dark sky pale.
static func fog_color(hour: float) -> Color:
	return sun_color(hour) * lerpf(0.03, 1.0, day_factor(hour))


## Building-window emission strength, 0 by day → 1 at night. Smooth (not the
## hysteresis switch) so windows fade in through dusk rather than popping.
static func window_emission(hour: float) -> float:
	return 1.0 - smoothstep(-4.0, 2.0, sun_elevation_deg(hour))


## Hysteresis switch for streetlights (and anything else that hard-toggles):
## turns ON below LIGHTS_ON_BELOW_DEG, then stays on until the sun climbs
## above LIGHTS_OFF_ABOVE_DEG. Pass the current state back in each call.
static func lights_on(elevation_deg: float, currently_on: bool) -> bool:
	if currently_on:
		return elevation_deg < LIGHTS_OFF_ABOVE_DEG
	return elevation_deg < LIGHTS_ON_BELOW_DEG


## Walk an open polyline and emit a point every `spacing` metres, each pushed
## `lateral_offset` metres to the segment's right — streetlight positions along
## a road centreline land on the kerb instead of mid-lane.
static func spaced_along(
	path: PackedVector2Array, spacing: float, lateral_offset: float = 0.0
) -> PackedVector2Array:
	var out := PackedVector2Array()
	if path.size() < 2 or spacing <= 0.0:
		return out
	var until_next := 0.0
	for i in range(path.size() - 1):
		var a := path[i]
		var b := path[i + 1]
		var seg := b - a
		var seg_len := seg.length()
		if seg_len < 0.001:
			continue
		var dir := seg / seg_len
		var right := Vector2(-dir.y, dir.x) * lateral_offset
		var travelled := until_next
		while travelled <= seg_len:
			out.append(a + dir * travelled + right)
			travelled += spacing
		until_next = travelled - seg_len
	return out
