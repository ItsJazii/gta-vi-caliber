class_name SunPath
extends RefCounted
## Where the sun is, and what it looks like, at a given clock hour — the pure math
## behind the day/night cycle (roadmap M4: "Time-of-day cycle driving sun"). The
## same DayClock that paces citizens' routines drives this, so dusk falls exactly
## as they head home to sleep.
##
## Scene-free and deterministic (hour in, angles/energy/colour out), so it
## unit-tests headless (tests/unit/test_sun_path.gd). A DayNightCycle node applies
## the result to a DirectionalLight3D each frame.

## Steepest the sun gets at solar noon (radians ≈ 74°).
const MAX_PITCH: float = 1.3
## Directional energy at noon.
const PEAK_ENERGY: float = 1.3
## Faint blue moonlight floor at night so the world isn't pitch black.
const NIGHT_ENERGY: float = 0.06


## Solar height in [-1, 1]: 0 at the 06:00/18:00 horizon, +1 at noon, -1 at
## midnight. A clean sine so dawn and dusk ease in symmetrically.
static func solar_height(hour: float) -> float:
	return sin((fposmod(hour, 24.0) - 6.0) / 12.0 * PI)


## Sun pitch in radians (positive = above horizon), for a light that aims down.
static func sun_pitch(hour: float) -> float:
	return solar_height(hour) * MAX_PITCH


## Sun yaw in radians, sweeping east (dawn) to west (dusk) across the day.
static func sun_yaw(hour: float) -> float:
	return (fposmod(hour, 24.0) - 6.0) / 12.0 * PI


## Is the sun above the horizon right now?
static func is_daytime(hour: float) -> bool:
	return solar_height(hour) > 0.0


## Directional light energy: ramps from the moonlight floor at the horizon up to
## PEAK_ENERGY at noon; stays at the floor all night.
static func energy(hour: float) -> float:
	var h := solar_height(hour)
	if h <= 0.0:
		return NIGHT_ENERGY
	return lerpf(NIGHT_ENERGY, PEAK_ENERGY, clampf(h, 0.0, 1.0))


## Light colour: cool blue moonlight at night, warm orange at the horizon
## (golden hour), easing to near-white at noon.
static func light_color(hour: float) -> Color:
	var h := solar_height(hour)
	var night := Color(0.45, 0.55, 0.85)
	if h <= 0.0:
		return night
	var horizon := Color(1.0, 0.55, 0.3)
	var noon := Color(1.0, 0.97, 0.92)
	return horizon.lerp(noon, clampf(h, 0.0, 1.0))


## Ambient light scale [0, 1] for a WorldEnvironment, so shadows lift at midday
## and deepen at night without ever crushing to black.
static func ambient_scale(hour: float) -> float:
	return lerpf(0.12, 1.0, clampf(solar_height(hour) * 0.5 + 0.5, 0.0, 1.0))


## Whether artificial lights (streetlights, lit windows) should be on: they flick
## on a touch before true dark, as the sun nears the horizon, like real dusk
## timers — and stay on until well after dawn.
static func lights_on(hour: float) -> bool:
	return solar_height(hour) < 0.1
