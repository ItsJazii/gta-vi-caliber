extends SceneTree
## Integration test for witness memory: shoot one citizen next to another and
## confirm the bystander records a lingering memory of the crime and then
## recognises the player standing nearby. The recall math is unit-tested in
## test_npc_memory.gd; this proves the Citizen wiring (panic → memory → recognise).
## Run: godot --headless --path game --script res://tests/witness_capture.gd

const Citizen = preload("res://scripts/npc/citizen.gd")
const NpcMemory = preload("res://scripts/npc/npc_memory.gd")

const SETTLE_FRAMES := 10
const WITNESS_FRAMES := 150

var _victim: Citizen = null
var _witness: Citizen = null
var _player: CharacterBody3D = null
var _frame := 0
var _phase := "settle"
var _failures: PackedStringArray = []


func _initialize() -> void:
	_build_ground()
	_player = CharacterBody3D.new()
	_player.name = "PlayerStub"
	_player.add_to_group("player")
	_player.position = Vector3(0, 1, 0)
	root.add_child(_player)
	_victim = _spawn("Victim", Vector3(3, 1.2, 0))
	_witness = _spawn("Witness", Vector3(5, 1.2, 0))


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		"settle":
			if _frame >= SETTLE_FRAMES:
				# A shot rings out next to the witness.
				_victim.take_damage(5.0, _victim.global_position, Vector3.UP)
				_phase = "witness"
				_frame = 0
		"witness":
			if _frame >= WITNESS_FRAMES:
				_check()
				return _finish()
	return _phase == "done"


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.add_to_group("world")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	root.add_child(body)


func _spawn(node_name: String, pos: Vector3) -> Citizen:
	var c: Citizen = load("res://scenes/npc/citizen.tscn").instantiate()
	c.name = node_name
	root.add_child(c)
	c.position = pos
	return c


func _check() -> void:
	var mem := _witness.crime_memory()
	if mem < NpcMemory.UNEASY:
		_fail("witness did not record the crime (memory %.2f)" % mem)
		return
	var dist := _witness.global_position.distance_to(_player.global_position)
	if not NpcMemory.recognizes(mem, dist):
		_fail("witness does not recognise the nearby player (mem %.2f, dist %.1f)" % [mem, dist])


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> bool:
	_phase = "done"
	if _failures.is_empty():
		print(
			(
				"witness: OK — bystander remembers the crime (%.2f) and recognises the culprit"
				% _witness.crime_memory()
			)
		)
		quit(0)
	else:
		for f in _failures:
			push_error("witness: %s" % f)
		quit(1)
	return true
