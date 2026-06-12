extends SceneTree
## Runtime probe for the live day/night cycle on the playable map (issue #10:
## night stuck at permanent golden hour). Boots miami.tscn and asserts the
## ramp actually carries the scene to true night and back: a clock node in
## group "sky" (the HUD's contract) whose time advances, sun energy and the
## streetlight CPU channel tracking the hour, the sky shader receiving the
## night amount, the HUD clock text following the time, and no static
## NightAmountPublisher stand-in left to fight the live controller.
## Run headless:
##   godot --headless --path game --script res://tests/miami_day_night_probe.gd

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const WARMUP_FRAMES: int = 90
const ADVANCE_FRAMES: int = 30
const SETTLE_FRAMES: int = 5

var _scene: Node = null
var _frames: int = 0
var _phase: String = "warmup"
var _phase_frame: int = 0
var _tod_at_warmup: float = -1.0
var _failures: PackedStringArray = []


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("miami day-night probe: scene failed to load")
		quit(1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	_phase_frame += 1
	var done := false
	match _phase:
		"warmup":
			done = _phase_warmup()
		"advancing":
			done = _phase_advancing()
		"noon":
			done = _phase_noon()
		"night":
			done = _phase_night()
	return done


func _phase_warmup() -> bool:
	if _phase_frame < WARMUP_FRAMES:
		return false
	var sky := _sky_clock()
	if sky == null:
		_failures.append("no time-of-day node in group 'sky' (HUD clock contract)")
		return _finish()
	_tod_at_warmup = sky.time_of_day
	_next("advancing")
	return false


func _phase_advancing() -> bool:
	if _phase_frame < ADVANCE_FRAMES:
		return false
	if is_equal_approx(_sky_clock().time_of_day, _tod_at_warmup):
		_failures.append(
			(
				"clock frozen: time_of_day still %.3f after %d frames"
				% [_tod_at_warmup, ADVANCE_FRAMES]
			)
		)
	_sky_clock().set_time_of_day(12.0)
	_next("noon")
	return false


func _phase_noon() -> bool:
	if _phase_frame < SETTLE_FRAMES:
		return false
	_check_noon()
	_sky_clock().set_time_of_day(22.0)
	_next("night")
	return false


func _phase_night() -> bool:
	if _phase_frame < SETTLE_FRAMES:
		return false
	_check_night()
	_check_no_static_publisher()
	return _finish()


func _check_noon() -> void:
	var sun := _sun()
	if sun == null:
		_failures.append("no DirectionalLight3D sun in the scene")
		return
	if sun.light_energy < 0.5:
		_failures.append("noon sun is dark: energy %.2f" % sun.light_energy)
	if StreetlightSwitch.night_level > 0.1:
		_failures.append("streetlight night_level %.2f at noon" % StreetlightSwitch.night_level)
	_check_hud_clock("noon")


func _check_night() -> void:
	var sun := _sun()
	if sun != null and sun.light_energy > 0.2:
		_failures.append("22:00 sun still bright: energy %.2f" % sun.light_energy)
	var expected := SkyModel.night_amount(22.0)
	if absf(StreetlightSwitch.night_level - expected) > 0.15:
		_failures.append(
			(
				"streetlight night_level %.2f at 22:00, expected ~%.2f"
				% [StreetlightSwitch.night_level, expected]
			)
		)
	var sky_night := _sky_shader_night_amount()
	if sky_night < 0.0:
		_failures.append("sky material is not the day/night ShaderMaterial sky")
	elif absf(sky_night - expected) > 0.15:
		_failures.append(
			"sky shader night_amount %.2f at 22:00, expected ~%.2f" % [sky_night, expected]
		)
	_check_hud_clock("night")


## The HUD clock label must follow the live clock (it renders "00:00" forever
## when nothing joins group "sky"). Tolerates the tiny drift the running clock
## adds between set_time_of_day and this frame.
func _check_hud_clock(label: String) -> void:
	var hud := get_first_node_in_group("game_hud")
	if hud == null:
		_failures.append("no game_hud in the scene")
		return
	var clock := hud.get_node_or_null("TopRight/Clock") as Label
	if clock == null:
		_failures.append("game_hud has no TopRight/Clock label")
		return
	var shown := clock.text
	var expected := HudFormat.format_clock(_sky_clock().time_of_day)
	if shown != expected:
		_failures.append("HUD clock reads '%s' at %s, expected '%s'" % [shown, label, expected])


## The static NightAmountPublisher stand-in re-publishes its fixed value every
## frame and would fight the live controller for the shader global.
func _check_no_static_publisher() -> void:
	for node in _scene.find_children("*", "Node", true, false):
		if node is NightAmountPublisher:
			_failures.append("static NightAmountPublisher still in the scene: %s" % node.name)


func _sky_clock() -> Node:
	return get_first_node_in_group("sky")


func _sun() -> DirectionalLight3D:
	return _scene.find_child("Sun", true, false) as DirectionalLight3D


## night_amount from the sky ShaderMaterial, or -1.0 when the sky is not the
## day/night shader (e.g. still the static ProceduralSkyMaterial).
func _sky_shader_night_amount() -> float:
	var we := _scene.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if we == null or we.environment == null or we.environment.sky == null:
		return -1.0
	var material := we.environment.sky.sky_material
	if material is not ShaderMaterial:
		return -1.0
	var value = (material as ShaderMaterial).get_shader_parameter("night_amount")
	return float(value) if value != null else -1.0


func _next(phase: String) -> void:
	_phase = phase
	_phase_frame = 0


func _finish() -> bool:
	if _failures.is_empty():
		print("miami day-night probe: OK (clock live, night reachable, HUD synced)")
		quit(0)
	else:
		for failure in _failures:
			push_error("miami day-night probe FAIL :: %s" % failure)
		print("miami day-night probe: %d failure(s)" % _failures.size())
		quit(1)
	return true
