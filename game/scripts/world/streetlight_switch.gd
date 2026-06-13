class_name StreetlightSwitch
extends Node
## Fades a streetlight material's emission with the day/night cycle so lamps glow
## at night and go dark by day, instead of being always-on props. Reads the
## shared `world_night_amount` global that SkyController publishes (one clock for
## the whole world) and drives the emission each frame. The pure mapping is in
## lamp_energy(); attach with a material + its lit energy via setup().

## CPU-side day/night level published by the scene's day/night driver
## (SkyController / DayNight) every frame: 0 = full day, 1 = full night. Read here
## instead of RenderingServer.global_shader_parameter_get, which is editor-only
## (errors + tanks performance when called per-frame in a running game).
static var night_level: float = 0.0

var _material: StandardMaterial3D = null
var _full_energy: float = 2.5
var _lights: Array[OmniLight3D] = []
var _light_full_energy: float = 0.0


## Emission energy for a night level: off in daylight, ramping to full at night.
static func lamp_energy(night_amount: float, full_energy: float) -> float:
	return full_energy * clampf(night_amount, 0.0, 1.0)


## Bind the lamp material whose emission this should drive, and the energy it
## reaches at full night (its authored daytime/peak emission multiplier).
func setup(material: StandardMaterial3D, full_energy: float) -> void:
	_material = material
	_full_energy = full_energy


## Bind real OmniLight3D pools to fade with the same clock as the emissive heads
## so the lamps actually pour warm light onto the street at night (and switch off
## — invisible, zero cost — by day). `full_energy` is their peak night energy.
func bind_lights(lights: Array[OmniLight3D], full_energy: float) -> void:
	_lights = lights
	_light_full_energy = full_energy


func _process(_delta: float) -> void:
	if _material != null:
		_material.emission_energy_multiplier = lamp_energy(night_level, _full_energy)
	if _lights.is_empty():
		return
	var energy := lamp_energy(night_level, _light_full_energy)
	var lit := energy > 0.001
	for light in _lights:
		if not is_instance_valid(light):
			continue
		# Hide the light outright by day so it costs nothing in the light cluster.
		light.visible = lit
		if lit:
			light.light_energy = energy
