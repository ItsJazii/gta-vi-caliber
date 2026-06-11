class_name TimeOfDay
extends Node
## Drives the day/night cycle for the world scene it sits in: advances the
## clock, aims and tints the sibling Sun (DirectionalLight3D), repaints the
## sibling WorldEnvironment's ProceduralSkyMaterial, switches streetlights
## (group "streetlight": visibility toggled with hysteresis) and fades building
## window glow (group "night_emissive": `set_night_amount(float)` called).
##
## All the colour/angle/threshold maths lives in DaylightMath so it stays
## headless-testable; this node is only the wiring. Scene-contained on purpose:
## it looks for its light and environment on the parent world scene (signals
## up, calls down — no autoload, no cross-scene paths).

signal hour_changed(hour: int)
signal night_began
signal night_ended

## Real minutes for one full 24 h in-game day.
@export_range(0.5, 120.0, 0.5) var day_length_minutes: float = 10.0
## Clock time at scene start, hours in [0, 24).
@export_range(0.0, 24.0, 0.01) var initial_hour: float = 13.0
## Freeze the clock (screenshots, missions forcing a time). Look still applies.
@export var paused: bool = false

## Current clock time, hours in [0, 24).
var hour: float = 13.0

var _sun: DirectionalLight3D
var _sky_material: ProceduralSkyMaterial
var _environment: Environment
var _night_on: bool = false
var _last_whole_hour: int = -1
var _last_window_emission: float = -1.0


func _ready() -> void:
	hour = fposmod(initial_hour, 24.0)
	_resolve_scene_handles()
	# Seed the hard switches to the starting hour without emitting transitions.
	_night_on = DaylightMath.lights_on(DaylightMath.sun_elevation_deg(hour), false)
	_last_whole_hour = int(hour)
	_set_streetlights(_night_on)
	_apply(hour)


func _process(delta: float) -> void:
	if not paused:
		hour = fposmod(hour + delta * 24.0 / (day_length_minutes * 60.0), 24.0)
	_apply(hour)


## Snap the clock to a specific hour (missions, debug, screenshot capture).
func set_hour(value: float) -> void:
	hour = fposmod(value, 24.0)
	_apply(hour)


func _apply(tod: float) -> void:
	var whole := int(tod)
	if whole != _last_whole_hour:
		_last_whole_hour = whole
		hour_changed.emit(whole)
	_update_sun(tod)
	_update_sky(tod)
	_update_night_state(tod)
	_update_window_emission(tod)


func _update_sun(tod: float) -> void:
	if _sun == null:
		return
	# A DirectionalLight emits along local -Z; aim it down the incoming ray.
	var forward := -DaylightMath.key_light_direction(tod)
	if forward.length_squared() > 1e-6:
		forward = forward.normalized()
		var up := Vector3.UP
		if absf(forward.dot(up)) > 0.999:
			up = Vector3.FORWARD
		var origin := _sun.global_transform.origin
		_sun.look_at_from_position(origin, origin + forward, up)
	_sun.light_energy = DaylightMath.sun_energy(tod)
	_sun.light_color = DaylightMath.sun_color(tod)
	# Shadows are wasted on the dim night key light.
	_sun.shadow_enabled = DaylightMath.sun_elevation_deg(tod) > -2.0


func _update_sky(tod: float) -> void:
	if _sky_material != null:
		var horizon := DaylightMath.sky_horizon_color(tod)
		_sky_material.sky_top_color = DaylightMath.sky_top_color(tod)
		_sky_material.sky_horizon_color = horizon
		_sky_material.ground_horizon_color = horizon
		_sky_material.ground_bottom_color = horizon * 0.4
	if _environment != null and _environment.fog_enabled:
		# Aerial perspective: warm at dusk, near-black at night. Keep fog off
		# most of the sky so the horizon gradient stays visible.
		_environment.fog_light_color = DaylightMath.fog_color(tod)
		_environment.fog_sky_affect = 0.25


func _update_night_state(tod: float) -> void:
	var night := DaylightMath.lights_on(DaylightMath.sun_elevation_deg(tod), _night_on)
	if night == _night_on:
		return
	_night_on = night
	_set_streetlights(night)
	if night:
		night_began.emit()
	else:
		night_ended.emit()


func _set_streetlights(on: bool) -> void:
	for light in get_tree().get_nodes_in_group("streetlight"):
		if light is Node3D:
			(light as Node3D).visible = on


func _update_window_emission(tod: float) -> void:
	var emission := DaylightMath.window_emission(tod)
	if absf(emission - _last_window_emission) < 0.01:
		return
	_last_window_emission = emission
	for target in get_tree().get_nodes_in_group("night_emissive"):
		if target.has_method("set_night_amount"):
			target.set_night_amount(emission)


## Find the Sun light and WorldEnvironment on the parent world scene. World
## scenes are self-contained, so siblings are the contract.
func _resolve_scene_handles() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for child in parent.get_children():
		if _sun == null and child is DirectionalLight3D:
			_sun = child as DirectionalLight3D
		elif _environment == null and child is WorldEnvironment:
			var we := child as WorldEnvironment
			_environment = we.environment
	if _environment != null and _environment.sky != null:
		var mat := _environment.sky.sky_material
		if mat is ProceduralSkyMaterial:
			_sky_material = mat as ProceduralSkyMaterial
