extends SceneTree
## Integration test for nav-routed citizens: drops a wall between a citizen and
## its workplace, sets the CityDirector's nav grid, and proves the citizen plans
## a path *around* the wall (not through it) and physically crosses to the far
## side — the roadmap M4 "navmesh flows" behaviour, built by reusing the swarm's
## NavGrid A* core. Without a nav grid this whole path is skipped and citizens
## walk straight (covered elsewhere); here we exercise the routed branch.
## Run: godot --headless --path game --script res://tests/nav_life_capture.gd

const CityDirector = preload("res://scripts/npc/city_director.gd")
const Citizen = preload("res://scripts/npc/citizen.gd")
const NavGrid = preload("res://scripts/ai/nav_grid.gd")

const MOVE_FRAMES := 1400
const SETTLE_FRAMES := 8

var _director: CityDirector = null
var _hero: Citizen = null
var _frame := 0
var _phase := "settle"
var _planned_path: Array = []
var _failures: PackedStringArray = []


func _initialize() -> void:
	_build_ground()
	_build_player(Vector3(40, 1, 40))
	_director = CityDirector.new()
	_director.name = "CityDirector"
	root.add_child(_director)
	# A 20x20 grid of 2 m cells spanning x,z in [-20, 20], with a wall at x≈0
	# blocking |z| < 6 — so the only way across is around z = ±7.
	var nav := NavGrid.new(20, 20, 2.0, Vector3(-20, 0, -20))
	nav.block_world_rect(Vector2(-1, -6), Vector2(1, 6))
	_director.nav = nav
	# Office on the far side of the wall.
	var office := Marker3D.new()
	office.name = "POI_office"
	office.add_to_group("poi_office")
	root.add_child(office)
	office.position = Vector3(12, 0, 0)
	_hero = _spawn_citizen("Barista", Vector3(-12, 1.2, 0), "doomsday_barista")


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		"settle":
			if _frame >= SETTLE_FRAMES:
				_plan()
				_phase = "move"
				_frame = 0
		"move":
			if _frame >= MOVE_FRAMES:
				_check_crossed()
				return _finish()
	return _phase == "done"


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.add_to_group("world")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 120)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	root.add_child(body)


func _build_player(pos: Vector3) -> void:
	var p := CharacterBody3D.new()
	p.name = "PlayerStub"
	p.add_to_group("player")
	p.position = pos
	root.add_child(p)


func _spawn_citizen(node_name: String, pos: Vector3, archetype: String) -> Citizen:
	var packed: PackedScene = load("res://scenes/npc/citizen.tscn")
	var c: Citizen = packed.instantiate()
	c.name = node_name
	c.archetype_id = archetype
	root.add_child(c)
	c.position = pos
	return c


func _plan() -> void:
	_director._clock.hour = 10.0  # work hour -> head to the office
	_hero._pick_new_target()
	_planned_path = _hero._path.duplicate()

	if _planned_path.size() < 2:
		_fail("no multi-point path planned (got %d points)" % _planned_path.size())
		return
	# No waypoint may sit on a blocked cell.
	for wp in _planned_path:
		var cell := _director.nav.world_to_cell(wp)
		if _director.nav.is_blocked(cell.x, cell.y):
			_fail("path waypoint %v lands on a blocked cell" % wp)
			return
	# The path must actually detour around the wall (reach past |z| = 5.5).
	var max_abs_z := 0.0
	for wp in _planned_path:
		max_abs_z = maxf(max_abs_z, absf((wp as Vector3).z))
	if max_abs_z < 5.5:
		_fail("path did not detour around the wall (max |z| = %.1f)" % max_abs_z)


func _check_crossed() -> void:
	# Started at x = -12; must have rounded the wall to the office side (x > 0).
	if _hero.global_position.x <= 0.0:
		_fail("citizen never crossed to the office side (x = %.1f)" % _hero.global_position.x)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> bool:
	_phase = "done"
	if _failures.is_empty():
		print(
			(
				"nav life: OK — citizen routed around the wall (%d waypoints) and reached x = %.1f"
				% [_planned_path.size(), _hero.global_position.x]
			)
		)
		quit(0)
	else:
		for f in _failures:
			push_error("nav life: %s" % f)
		quit(1)
	return true
