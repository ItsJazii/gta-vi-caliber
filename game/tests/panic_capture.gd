extends SceneTree
## Integration test for panic contagion: line up citizens, frighten one, and
## prove the terror ripples down the line citizen-to-citizen — one gunshot empties
## a street. Exercises Citizen._maybe_catch_panic + NpcReaction.catches_panic
## (the threshold math is unit-tested separately).
## Run: godot --headless --path game --script res://tests/panic_capture.gd

const Citizen = preload("res://scripts/npc/citizen.gd")

const COUNT := 4
const SPREAD_FRAMES := 240
const SETTLE_FRAMES := 10

var _citizens: Array = []
var _frame := 0
var _phase := "settle"
var _failures: PackedStringArray = []


func _initialize() -> void:
	_build_ground()
	# A tight row, 3 m apart — each within the other's panic radius.
	for i in COUNT:
		var c := _spawn_citizen("Pedestrian%d" % i, Vector3(i * 3.0, 1.2, 0))
		_citizens.append(c)


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		"settle":
			if _frame >= SETTLE_FRAMES:
				# Frighten the citizen at one end of the line.
				_citizens[0].take_damage(5.0, _citizens[0].global_position, Vector3.UP)
				_phase = "spread"
				_frame = 0
		"spread":
			if _frame >= SPREAD_FRAMES:
				_check()
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


func _spawn_citizen(node_name: String, pos: Vector3) -> Citizen:
	var packed: PackedScene = load("res://scenes/npc/citizen.tscn")
	var c: Citizen = packed.instantiate()
	c.name = node_name
	root.add_child(c)
	c.position = pos
	return c


func _check() -> void:
	var panicking := 0
	for c in _citizens:
		if c.is_panicking():
			panicking += 1
	# The shot citizen plus the wave should leave most of the line running.
	if panicking < 3:
		_fail("panic reached only %d / %d citizens — contagion not spreading" % [panicking, COUNT])


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> bool:
	_phase = "done"
	if _failures.is_empty():
		var panicking := 0
		for c in _citizens:
			if c.is_panicking():
				panicking += 1
		print("panic: OK — one scare sent %d / %d citizens fleeing" % [panicking, COUNT])
		quit(0)
	else:
		for f in _failures:
			push_error("panic: %s" % f)
		quit(1)
	return true
