class_name WeatherEffects
extends RefCounted
## Pure weather-on-gameplay math — the layer that makes rain and fog actually
## *matter*. WeatherController/WeatherState own the front cycle and produce a
## wetness/fog level; this reads those normalized 0..1 levels and turns them into
## the knobs gameplay systems consume: tyre grip, braking distance, sight range,
## traffic speed, and hydroplaning. It owns no state and no nodes.
##
## Static math only, same testable-core pattern as VehicleHandling
## (docs/ARCHITECTURE.md): float in / float out, defensive throughout. Every
## input is clamped to its valid range, every output clamped to a safe band, and
## no path produces a NaN. Multipliers are monotonic in wetness/fog and collapse
## to the neutral 1.0 / base values in dry, clear conditions. Covered by
## tests/unit/test_weather_effects.gd.

## Grip retained on fully soaked asphalt (1.0 dry). Cars slide more in rain.
const SOAKED_GRIP: float = 0.7
## Stopping distance stretches up to this multiple of the dry distance when wet.
const MAX_BRAKE_STRETCH: float = 1.6
## Fraction of base view distance fog can eat at fog = 1.0.
const FOG_VISIBILITY_BITE: float = 0.6
## Floor on visible range so a system never gets a zero/negative sight distance.
const MIN_VISIBILITY: float = 5.0
## How far AI sight shrinks at full wetness and full fog respectively.
const RAIN_SIGHT_BITE: float = 0.25
const FOG_SIGHT_BITE: float = 0.55
## Slowest AI sight allowed, so cops/NPCs never go fully blind.
const MIN_SIGHT: float = 0.3
## Traffic crawls to this fraction of its dry speed when fully soaked.
const SOAKED_TRAFFIC_SPEED: float = 0.75


## Clamp any external 0..1 level defensively. Genuinely NaN-safe: clampf(NaN)
## returns NaN (every NaN comparison is false, so neither bound applies), which
## would then poison grip/brake/sight/traffic/hydroplane and the whole physics
## chain — so collapse a non-finite level to 0 (dry) first.
static func _level(x: float) -> float:
	if is_nan(x):
		return 0.0
	return clampf(x, 0.0, 1.0)


## Lateral/longitudinal grip scale: 1.0 dry, easing down to SOAKED_GRIP soaked.
## Monotonically decreasing in wetness. Feed into VehicleHandling's base_grip.
static func grip_multiplier(wetness: float) -> float:
	return lerpf(1.0, SOAKED_GRIP, _level(wetness))


## Braking-distance scale, always >= 1.0: a wet road needs more room to stop.
## 1.0 dry, stretching to MAX_BRAKE_STRETCH soaked. Monotonically increasing.
static func brake_distance_multiplier(wetness: float) -> float:
	return lerpf(1.0, MAX_BRAKE_STRETCH, _level(wetness))


## View distance after fog: full base_range at fog 0, reduced as fog rises, never
## below MIN_VISIBILITY. A negative base_range is treated as the floor.
static func visibility_range(base_range: float, fog: float) -> float:
	var base := maxf(base_range, MIN_VISIBILITY)
	var reduced := base * (1.0 - _level(fog) * FOG_VISIBILITY_BITE)
	return maxf(reduced, MIN_VISIBILITY)


## How far cops/NPCs can see, as a fraction of their clear-weather range: 1.0 in
## clear/dry, dropping with both rain and fog (fog bites harder), floored at
## MIN_SIGHT. Multiply a detection range by this. Monotonic in both inputs.
static func ai_sight_multiplier(wetness: float, fog: float) -> float:
	var loss := _level(wetness) * RAIN_SIGHT_BITE + _level(fog) * FOG_SIGHT_BITE
	return clampf(1.0 - loss, MIN_SIGHT, 1.0)


## Traffic cruise-speed scale: 1.0 dry, easing to SOAKED_TRAFFIC_SPEED soaked.
## Monotonically decreasing — cars ease off in the rain.
static func traffic_speed_multiplier(wetness: float) -> float:
	return lerpf(1.0, SOAKED_TRAFFIC_SPEED, _level(wetness))


## Hydroplane risk in [0, 1]: 0 when dry or at/below threshold_speed, rising with
## both wetness and how far speed exceeds the threshold. Speeds are in the same
## unit (m/s or km/h) as threshold_speed; a non-positive threshold yields 0.
static func hydroplane_risk(wetness: float, speed: float, threshold_speed: float) -> float:
	var wet := _level(wetness)
	if wet <= 0.0 or threshold_speed <= 0.0:
		return 0.0
	var over := maxf(speed, 0.0) - threshold_speed
	if over <= 0.0:
		return 0.0
	# Risk saturates one threshold's worth of speed past the threshold.
	var speed_factor := clampf(over / threshold_speed, 0.0, 1.0)
	return clampf(wet * speed_factor, 0.0, 1.0)


## Whether headlights should be on: true in meaningful fog or once it's getting
## dark. Both inputs are 0..1 (fog level, night amount). Clear bright day = false.
static func headlights_recommended(fog: float, night_amount: float) -> bool:
	return _level(fog) >= 0.4 or _level(night_amount) >= 0.4
