class_name DayNightCycle
extends Node3D
## Drives a scene's sun (and ambient) from the city clock, so the world visibly
## cycles day→dusk→night→dawn while citizens run their routines — the visual half
## of roadmap M4's "Time-of-day cycle driving sun". All the math is in SunPath
## (pure, tested); this node just reads the hour and applies the result each frame.
##
## Reads the hour from a CityDirector (group "city_director") when one is present,
## so the sun and the crowd share a single clock — dusk lands exactly as they head
## home to sleep. With no director it falls back to its own DayClock, so it still
## works dropped into a bare scene.

## The sun to drive. Defaults to a sibling named "Sun" if left empty.
@export var sun_path: NodePath
## Optional WorldEnvironment whose ambient energy follows the sun.
@export var environment_path: NodePath
## Used only when no CityDirector is in the scene.
@export_range(0.0, 24.0) var fallback_start_hour: float = 8.0
@export var fallback_day_length_sec: float = 180.0

var _sun: DirectionalLight3D = null
var _env: WorldEnvironment = null
var _clock: DayClock = null
var _base_ambient_energy: float = 1.0
# -1 = unknown, so the first frame always pushes the correct state.
var _lights_state: int = -1


func _ready() -> void:
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	if _sun == null:
		_sun = get_node_or_null(^"../Sun") as DirectionalLight3D
	_env = get_node_or_null(environment_path) as WorldEnvironment
	if _env != null and _env.environment != null:
		_base_ambient_energy = _env.environment.ambient_light_energy
	_clock = DayClock.new(fallback_start_hour, fallback_day_length_sec)
	_apply(_hour())


func _process(delta: float) -> void:
	# Only advance the local clock when no director owns one (avoids double time).
	if _city_director() == null:
		_clock.advance(delta)
	_apply(_hour())


func _apply(hour: float) -> void:
	if _sun != null:
		# Negative pitch so a sun above the horizon casts its light downward.
		_sun.rotation = Vector3(-SunPath.sun_pitch(hour), SunPath.sun_yaw(hour), 0.0)
		_sun.light_energy = SunPath.energy(hour)
		_sun.light_color = SunPath.light_color(hour)
	if _env != null and _env.environment != null:
		_env.environment.ambient_light_energy = _base_ambient_energy * SunPath.ambient_scale(hour)
	_apply_night_lights(hour)


## Flick streetlights and lit windows (group "night_lights") on at dusk, off at
## dawn. Only touches the group when the state actually changes, so it costs
## nothing on the vast majority of frames.
func _apply_night_lights(hour: float) -> void:
	var want := 1 if SunPath.lights_on(hour) else 0
	if want == _lights_state:
		return
	_lights_state = want
	var on := want == 1
	for node in get_tree().get_nodes_in_group("night_lights"):
		var n3 := node as Node3D
		if n3 != null:
			n3.visible = on


func _hour() -> float:
	var director := _city_director()
	return director.hour() if director != null else _clock.hour


func _city_director() -> CityDirector:
	var nodes := get_tree().get_nodes_in_group("city_director")
	return nodes[0] as CityDirector if not nodes.is_empty() else null
