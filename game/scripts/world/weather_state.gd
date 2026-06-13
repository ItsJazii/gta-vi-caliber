class_name WeatherState
extends RefCounted
## A weather front and its aftermath — the pure model behind roadmap M4's
## "Weather fronts: clear → overcast → rain, wet-surface materials". Holds three
## values that the WeatherController turns into fog, rain, and shiny wet streets:
##   cloudiness 0..1 (clear → overcast), rain 0..1 (dry → downpour),
##   wetness 0..1 (how soaked surfaces are — lags rain, drying out slowly after).
##
## Scene-free and deterministic (a front is a function of a cycle position; the
## integrator is plain math), so it unit-tests headless
## (tests/unit/test_weather_state.gd). Pairs with the day/night cycle without
## fighting it — weather owns fog/rain/wetness, DayNightCycle owns the sun.

## How fast cloudiness/rain ease toward their front targets (per second).
const EASE_RATE: float = 0.5
## Wetness gain per second at full rain, and dry-out per second when it stops.
const WET_RATE: float = 0.25
const DRY_RATE: float = 0.08

var cloudiness: float = 0.0
var rain: float = 0.0
var wetness: float = 0.0


## The front's target (cloudiness, rain) at a position in its 0..1 cycle: a calm
## clear opening, clouds rolling in, a rain band that swells and fades, then
## clearing skies. Wraps, so a controller can just advance the position forever.
static func front_targets(cycle_pos: float) -> Dictionary:
	var p := fposmod(cycle_pos, 1.0)
	var cloud := 0.0
	var rn := 0.0
	if p < 0.25:
		cloud = lerpf(0.25, 0.0, p / 0.25)  # last of the clouds clearing off
	elif p < 0.5:
		cloud = lerpf(0.0, 1.0, (p - 0.25) / 0.25)  # overcast building
	elif p < 0.75:
		cloud = 1.0
		rn = sin((p - 0.5) / 0.25 * PI)  # rain band swells then fades
	else:
		cloud = lerpf(1.0, 0.25, (p - 0.75) / 0.25)  # breaking up
	return {"cloud": clampf(cloud, 0.0, 1.0), "rain": clampf(rn, 0.0, 1.0)}


## Sky-shader cloud coverage for a given cloudiness: a clear day keeps a few
## fair-weather clouds (so the sky never reads sterile) and a storm stops just
## short of a solid slab (so sun glow still breaks the edges).
static func sky_cloud_coverage(cloud_amount: float) -> float:
	return lerpf(0.22, 0.95, clampf(cloud_amount, 0.0, 1.0))


## How storm-dark the sky shader should render (0 bright .. 0.85 charcoal).
## Fair-weather cloud (< ~0.35) keeps the sky bright; the slab only darkens as
## real overcast builds, so the front visibly *weighs* on the city.
static func sky_storm_darkness(cloud_amount: float) -> float:
	return smoothstep(0.35, 1.0, clampf(cloud_amount, 0.0, 1.0)) * 0.85


## Key-light (sun/moon) energy scale under cloud: full strength in clear air,
## dropping to ~35% under a solid storm deck — the "sun dims" half of the
## weather-reactive atmosphere. The curve matches sky_storm_darkness so the
## light fades in step with the sky it lights.
static func sun_dim_factor(cloud_amount: float) -> float:
	return lerpf(1.0, 0.35, smoothstep(0.35, 1.0, clampf(cloud_amount, 0.0, 1.0)))


## Ease toward a target sky and integrate surface wetness for `dt` seconds.
func step(dt: float, cloud_target: float, rain_target: float) -> void:
	cloudiness = move_toward(cloudiness, clampf(cloud_target, 0.0, 1.0), EASE_RATE * dt)
	rain = move_toward(rain, clampf(rain_target, 0.0, 1.0), EASE_RATE * dt)
	if rain > 0.1:
		wetness = minf(wetness + WET_RATE * dt * rain, 1.0)
	else:
		wetness = maxf(wetness - DRY_RATE * dt, 0.0)


## A human-readable condition for a debug HUD / dialogue ("nice weather for it").
func label() -> String:
	if rain > 0.2:
		return "rain"
	if cloudiness > 0.6:
		return "overcast"
	if cloudiness > 0.25:
		return "cloudy"
	return "clear"
