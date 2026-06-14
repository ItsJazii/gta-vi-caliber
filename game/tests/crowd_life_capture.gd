extends SceneTree
## Synthesis integration test: the swarm's CrowdDirector streams the crowd, and
## because Citizen extends Pedestrian, pointing its `pedestrian_scene` at
## citizen.tscn makes that streamed crowd *alive* — every spawned body runs a
## daily routine and banters — at no extra wiring. This guards that the two
## independently-built halves (streaming + life-sim) compose.
##
## Builds a player + a CityDirector with POIs + a CrowdDirector set to citizen.tscn,
## drives spawn ticks deterministically, and asserts the streamed bodies are
## Citizens that are actually saying something.
## Run: godot --headless --path game --script res://tests/crowd_life_capture.gd

const CityDirector = preload("res://scripts/npc/city_director.gd")
const CrowdDirector = preload("res://scripts/npc/crowd_director.gd")
const Citizen = preload("res://scripts/npc/citizen.gd")

const POIS := {"office": Vector3(8, 0, 0), "diner": Vector3(-8, 0, 0), "bar": Vector3(0, 0, 8)}
const SPAWN_TICKS := 12
const SETTLE_FRAMES := 8

var _crowd: CrowdDirector = null
var _frame := 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	_build_player(Vector3(0, 1, 0))
	_build_city_director()
	_build_pois()
	_build_crowd_director()


func _process(_delta: float) -> bool:
	_frame += 1
	# Drive spawn ticks by hand (one forced director tick per frame) so the test
	# doesn't depend on headless physics-step wall-clock timing.
	if _frame <= SPAWN_TICKS:
		_crowd._physics_process(0.6)  # > tick_interval, so each call spawns a batch
		return false
	if _frame < SPAWN_TICKS + SETTLE_FRAMES:
		return false
	_check()
	return _finish()


func _build_player(pos: Vector3) -> void:
	var p := CharacterBody3D.new()
	p.name = "PlayerStub"
	p.add_to_group("player")
	p.position = pos
	root.add_child(p)


func _build_city_director() -> void:
	var d := CityDirector.new()
	d.name = "CityDirector"
	d.day_length_sec = 600.0
	root.add_child(d)


func _build_pois() -> void:
	for place in POIS:
		var m := Marker3D.new()
		m.name = "POI_%s" % place
		m.add_to_group("poi_%s" % place)
		root.add_child(m)
		m.position = POIS[place]


func _build_crowd_director() -> void:
	_crowd = CrowdDirector.new()
	_crowd.name = "CrowdDirector"
	_crowd.pedestrian_scene = load("res://scenes/npc/citizen.tscn")
	_crowd.target_count = 8
	_crowd.spawn_budget = 3
	_crowd.snap_to_ground = false  # flat test world, no ground collider needed
	_crowd.spawn_min_radius = 6.0
	_crowd.spawn_max_radius = 12.0
	_crowd.cull_radius = 40.0
	root.add_child(_crowd)


func _check() -> void:
	var pop := _crowd.population()
	if pop < 6:
		_fail("crowd only reached %d / 8 streamed bodies" % pop)

	var citizens := get_nodes_in_group("citizens")
	if citizens.is_empty():
		_fail("streamed bodies are not Citizens (none joined the 'citizens' group)")
		return

	var alive_talking := 0
	for node in citizens:
		if node is not Citizen:
			_fail("a streamed body is not a Citizen: %s" % node)
			return
		var bubble := (node as Node).get_node_or_null("Bubble") as Label3D
		if bubble != null and bubble.text != "":
			alive_talking += 1
	if alive_talking == 0:
		_fail("streamed citizens spawned but none are living a routine / talking")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> bool:
	if _failures.is_empty():
		print(
			(
				"crowd life: OK — CrowdDirector streamed %d living, talking citizens"
				% _crowd.population()
			)
		)
		quit(0)
	else:
		for f in _failures:
			push_error("crowd life: %s" % f)
		quit(1)
	return true
