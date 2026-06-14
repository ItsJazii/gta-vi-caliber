extends SceneTree
## Headless integration test for the living-city stack: builds a tiny city in
## code (ground, a CityDirector with POIs, a handful of Citizens, a parked
## player) and proves the daily-life loop actually runs end to end —
##   1. citizens follow a routine: across a swept day, a Citizen visits several
##      distinct activities, not one;
##   2. they walk to the *right* place: at work-hour the target sits on the
##      office POI; at lunch, the diner;
##   3. they actually move when ticked; and
##   4. every citizen is saying something (the bark/bubble wired up).
##
## Pure-logic layers are unit-tested separately; this exercises the Node glue
## (Citizen extends Pedestrian + CityDirector) that the unit runner can't reach.
## Run:  godot --headless --path game --script res://tests/npc_life_capture.gd

const CityDirector = preload("res://scripts/npc/city_director.gd")
const Citizen = preload("res://scripts/npc/citizen.gd")

const POIS := {
	"home": Vector3(-20, 0, -20),
	"office": Vector3(20, 0, -20),
	"diner": Vector3(20, 0, 20),
	"park": Vector3(-20, 0, 20),
	"bar": Vector3(0, 0, 28),
	"gym": Vector3(28, 0, 0),
	"restroom": Vector3(-28, 0, 0),
	"street": Vector3(0, 0, 0),
}
const SWEEP_HOURS: PackedFloat32Array = [8.0, 10.0, 12.7, 14.0, 18.5, 20.0, 23.5]
const SETTLE_FRAMES := 24
const MOVE_FRAMES := 150

var _director: CityDirector = null
var _citizens: Array = []
var _hero: Citizen = null
var _frame := 0
var _phase := "settle"
var _hero_activities := {}
var _work_target := Vector3.ZERO
var _lunch_target := Vector3.ZERO
var _start_positions := {}
var _failures: PackedStringArray = []


func _initialize() -> void:
	_build_ground()
	_build_player(Vector3(60, 1, 60))  # parked far away so nobody flees mid-sweep
	_build_director()
	_build_pois()
	# One known persona we can assert a full routine against, plus a varied crowd.
	_hero = _spawn_citizen("Barista", Vector3(0, 1.2, 0), "doomsday_barista")
	_citizens.append(_hero)
	for i in 5:
		var c := _spawn_citizen("Cit%d" % i, Vector3(2 + i * 1.5, 1.2, 2.0), "")
		_citizens.append(c)


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		"settle":
			if _frame >= SETTLE_FRAMES:
				_run_day_sweep()
				_begin_move_phase()
				_phase = "move"
				_frame = 0
		"move":
			if _frame >= MOVE_FRAMES:
				_check_movement()
				_check_barks()
				return _finish()
	return _phase == "done"


# --- world construction -----------------------------------------------------


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.add_to_group("world")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	root.add_child(body)


func _build_player(pos: Vector3) -> void:
	var p := CharacterBody3D.new()
	p.name = "PlayerStub"
	p.add_to_group("player")
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 1.8
	cap.radius = 0.4
	shape.shape = cap
	shape.position = Vector3(0, 0.9, 0)
	p.add_child(shape)
	root.add_child(p)
	p.position = pos


func _build_director() -> void:
	_director = CityDirector.new()
	_director.name = "CityDirector"
	_director.start_hour = 8.0
	_director.day_length_sec = 1440.0
	root.add_child(_director)


func _build_pois() -> void:
	for place in POIS:
		var m := Marker3D.new()
		m.name = "POI_%s" % place
		m.add_to_group("poi_%s" % place)
		root.add_child(m)
		m.position = POIS[place]


func _spawn_citizen(node_name: String, pos: Vector3, archetype: String) -> Citizen:
	var packed: PackedScene = load("res://scenes/npc/citizen.tscn")
	var c: Citizen = packed.instantiate()
	c.name = node_name
	if archetype != "":
		c.archetype_id = archetype
	root.add_child(c)
	c.position = pos
	return c


# --- the day sweep (deterministic, hour-driven) -----------------------------


func _run_day_sweep() -> void:
	# Drive the clock by hand and force each citizen to replan, recording what the
	# hero chooses to do and where it decides to go.
	for hour in SWEEP_HOURS:
		_director._clock.hour = hour
		for c in _citizens:
			c._pick_new_target()
		_hero_activities[_hero._activity] = true
		if absf(hour - 10.0) < 0.01:
			_work_target = _hero._target
		elif absf(hour - 12.7) < 0.01:
			_lunch_target = _hero._target

	if _hero_activities.size() < 4:
		_fail(
			(
				"hero visited only %d distinct activities across the day (want >= 4): %s"
				% [_hero_activities.size(), str(_hero_activities.keys())]
			)
		)
	# At 10:00 a 9-to-5 barista should be heading to the office POI.
	if _work_target.distance_to(POIS["office"]) > 3.0:
		_fail("work-hour target %v not on office POI %v" % [_work_target, POIS["office"]])
	# At 12:42 it should be lunch at the diner.
	if _lunch_target.distance_to(POIS["diner"]) > 3.0:
		_fail("lunch-hour target %v not on diner POI %v" % [_lunch_target, POIS["diner"]])


func _begin_move_phase() -> void:
	# Send everyone to work and snapshot where they start, so we can confirm they
	# physically walk there over the next stretch of frames.
	_director._clock.hour = 10.0
	for c in _citizens:
		c._pick_new_target()
		_start_positions[c] = c.global_position


func _check_movement() -> void:
	var movers := 0
	for c in _citizens:
		var start: Vector3 = _start_positions[c]
		if c.global_position.distance_to(start) > 0.5:
			movers += 1
	if movers == 0:
		_fail("no citizen moved over %d frames — locomotion not wired" % MOVE_FRAMES)


func _check_barks() -> void:
	for c in _citizens:
		var bubble := c.get_node_or_null("Bubble") as Label3D
		if bubble == null or bubble.text == "":
			_fail("citizen %s never said anything" % c.name)
			return


# --- result -----------------------------------------------------------------


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> bool:
	_phase = "done"
	if _failures.is_empty():
		print(
			(
				"npc life: OK — hero lived %d activities, crowd of %d walked and talked"
				% [_hero_activities.size(), _citizens.size()]
			)
		)
		quit(0)
	else:
		for f in _failures:
			push_error("npc life: %s" % f)
		quit(1)
	return true
