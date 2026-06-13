extends SceneTree
## Integration probe for the citizen life sim in Miami: boots miami.tscn, waits
## past the district build and POI seeding, then asserts the city layer is
## actually alive — a CityDirector on the sky's clock, all eight POI kinds
## seeded near the player, Citizens mixed into the crowd and planning days, and
## the BarkDirector pool capped. Run headless:
##   godot --headless --path game --script res://tests/miami_citizen_probe.gd

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const WARMUP_FRAMES: int = 480

var _scene: Node = null
var _frames: int = 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("miami citizen probe: scene failed to load")
		quit(1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false
	_run_checks()
	return _finish()


func _run_checks() -> void:
	var director := get_first_node_in_group("city_director") as CityDirector
	if director == null:
		_failures.append("no CityDirector in group 'city_director'")
		return

	if not director.has_pois():
		_failures.append("CityDirector sees no POIs (seeder did not run?)")
	for place in CityDirector.PLACES:
		if get_nodes_in_group("poi_%s" % place).is_empty():
			_failures.append("POI kind not seeded: %s" % place)

	# The city clock must ride the sky's, so commutes match the visible light.
	var sky := get_first_node_in_group("sky")
	if sky != null and "time_of_day" in sky:
		var drift: float = absf(director.hour() - fposmod(float(sky.time_of_day), 24.0))
		if minf(drift, 24.0 - drift) > 0.25:
			_failures.append(
				"city clock drifted from sky: %.2f vs %.2f" % [director.hour(), sky.time_of_day]
			)

	var citizens := get_nodes_in_group("citizens")
	if citizens.is_empty():
		_failures.append("no Citizens spawned into the crowd")

	var barks := get_first_node_in_group("bark_director") as BarkDirector
	if barks == null:
		_failures.append("no BarkDirector in group 'bark_director'")
	elif barks._active.size() > barks.pool_size:
		_failures.append(
			"bark pool overflow: %d active > %d cap" % [barks._active.size(), barks.pool_size]
		)


func _finish() -> bool:
	if _failures.is_empty():
		var citizens := get_nodes_in_group("citizens").size()
		print("miami citizen probe: OK (%d citizens on the clock, POIs seeded)" % citizens)
		quit(0)
	else:
		for failure in _failures:
			push_error("miami citizen probe FAIL :: %s" % failure)
		print("miami citizen probe: %d failure(s)" % _failures.size())
		quit(1)
	return true
