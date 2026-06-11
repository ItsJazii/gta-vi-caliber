extends SceneTree
## Integration test for DayNightCycle: confirms the node reads the shared
## CityDirector clock and actually drives a DirectionalLight3D — bright sun high
## overhead at noon, dark sun below the horizon at midnight. The angle/colour
## math itself is unit-tested in test_sun_path.gd; this guards the node wiring.
## Run: godot --headless --path game --script res://tests/daynight_capture.gd

var _sun: DirectionalLight3D = null
var _director: CityDirector = null
var _cycle: DayNightCycle = null
var _streetlight: OmniLight3D = null
var _frame := 0
var _noon := {}
var _midnight := {}
var _failures: PackedStringArray = []


func _initialize() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	root.add_child(_sun)
	_director = CityDirector.new()
	_director.name = "CityDirector"
	root.add_child(_director)
	_streetlight = OmniLight3D.new()
	_streetlight.name = "Streetlight"
	_streetlight.add_to_group("night_lights")
	_streetlight.visible = false
	root.add_child(_streetlight)
	_cycle = DayNightCycle.new()
	_cycle.name = "DayNightCycle"
	root.add_child(_cycle)  # resolves Sun via the ../Sun fallback in _ready


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_director._clock.hour = 12.0
		_cycle._process(0.0)
		_noon = {
			"energy": _sun.light_energy,
			"pitch": _sun.rotation.x,
			"color": _sun.light_color,
			"lights": _streetlight.visible,
		}
	elif _frame == 4:
		_director._clock.hour = 0.0
		_cycle._process(0.0)
		_midnight = {
			"energy": _sun.light_energy, "pitch": _sun.rotation.x, "lights": _streetlight.visible
		}
		_check()
		return _finish()
	return false


func _check() -> void:
	if float(_noon["energy"]) <= float(_midnight["energy"]):
		_fail(
			(
				"noon not brighter than midnight (%.2f vs %.2f)"
				% [_noon["energy"], _midnight["energy"]]
			)
		)
	# Noon sun aims down (rotation.x = -pitch, pitch > 0 -> negative); midnight up.
	if float(_noon["pitch"]) >= 0.0:
		_fail("noon sun does not aim downward (rotation.x = %.2f)" % _noon["pitch"])
	if float(_midnight["pitch"]) <= 0.0:
		_fail("midnight sun is not below the horizon (rotation.x = %.2f)" % _midnight["pitch"])
	# Noon light should read warm-white, not the cool night blue.
	var c: Color = _noon["color"]
	if c.r < 0.9:
		_fail("noon light is not warm-white (r = %.2f)" % c.r)
	# Streetlights off at noon, on at midnight.
	if bool(_noon["lights"]):
		_fail("streetlights are on at noon")
	if not bool(_midnight["lights"]):
		_fail("streetlights did not switch on at midnight")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> bool:
	if _failures.is_empty():
		print(
			(
				"daynight: OK — sun tracks the city clock (noon energy %.2f, midnight %.2f)"
				% [_noon["energy"], _midnight["energy"]]
			)
		)
		quit(0)
	else:
		for f in _failures:
			push_error("daynight: %s" % f)
		quit(1)
	return true
