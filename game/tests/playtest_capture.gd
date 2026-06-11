extends SceneTree
## Headed QA playtest: boots real scenes, simulates input, asserts the player
## actually moves and can drive the car, and saves screenshots for visual
## review. Needs a renderer — run WITHOUT --headless:
##   godot --path game --script res://tests/playtest_capture.gd
## Screenshots land in /tmp/gta6_playtest/. Not part of check.sh (CI is headless).

const OUT_DIR := "/tmp/gta6_playtest"
const WALK_FRAMES := 180
const DRIVE_FRAMES := 240

var _frame := 0
var _phase := "boot"
var _start_pos := Vector3.ZERO
var _absolute_target := Vector3.ZERO
var _idle_engine_pitch := 0.0
var _failures: PackedStringArray = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	change_scene_to_file("res://scenes/world/sandbox.tscn")


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		"boot":
			_phase_boot()
		"walk":
			_phase_walk()
		"approach_car":
			_phase_approach_car()
		"drive":
			_phase_drive()
		"exit_car":
			_phase_exit_car()
		"district_load":
			if _frame >= 120:
				_shot("district_downtown")
				_begin_origin_test()
		"origin_shift":
			if _frame >= 10:
				_check_origin_shift()
				return _finish()
	return _phase == "done"


## Stride the player 5 km out and let FloatingOrigin pull the world back.
## The player crosses 5 km of world on purpose; what must NOT change is the
## relationship between world objects (sun vs ground), and the reconstructed
## absolute position must reflect the full 5 km.
func _begin_origin_test() -> void:
	var player := _player()
	var sun := current_scene.get_node_or_null("Sun") as Node3D
	var ground := current_scene.get_node_or_null("Ground") as Node3D
	if player == null or sun == null or ground == null:
		_failures.append("origin test: missing player/Sun/Ground reference nodes")
		_finish()
		return
	_start_pos = sun.global_position - ground.global_position
	_absolute_target = player.global_position + Vector3(5000.0, 0.0, 0.0)
	player.global_position = _absolute_target
	_next("origin_shift")


func _check_origin_shift() -> void:
	var player := _player()
	var sun := current_scene.get_node_or_null("Sun") as Node3D
	var ground := current_scene.get_node_or_null("Ground") as Node3D
	var origin := current_scene.get_node_or_null("FloatingOrigin")
	var planar := Vector3(player.global_position.x, 0.0, player.global_position.z)
	var world_drift := (sun.global_position - ground.global_position - _start_pos).length()
	print(
		(
			"playtest: after 5 km teleport player sits %.0f m from origin, world drift %.2f m"
			% [planar.length(), world_drift]
		)
	)
	if planar.length() > 4900.0:
		_failures.append(
			"floating origin never shifted (player still %.0f m out)" % planar.length()
		)
	if world_drift > 0.01:
		_failures.append("world geometry tore apart during shift (%.2f m)" % world_drift)
	if origin != null:
		var offset: Vector3 = origin.origin_offset
		var absolute := OriginMath.to_absolute(player.global_position, offset)
		if absolute.distance_to(_absolute_target) > 1.0:
			_failures.append(
				(
					"absolute position lost: reconstructed %v, expected %v"
					% [absolute, _absolute_target]
				)
			)


func _phase_boot() -> void:
	if _frame < 60:
		return
	_shot("sandbox_idle")
	var player := _player()
	if player == null:
		_failures.append("no node in 'player' group after sandbox boot")
		_to_district()
		return
	_start_pos = player.global_position
	Input.action_press("move_forward")
	_next("walk")


func _phase_walk() -> void:
	if _frame < WALK_FRAMES:
		return
	Input.action_release("move_forward")
	_shot("sandbox_walked")
	var moved := _player().global_position.distance_to(_start_pos)
	print("playtest: player walked %.2f m in %d frames" % [moved, WALK_FRAMES])
	if moved < 2.0:
		_failures.append("player barely moved (%.2f m) — input/locomotion broken" % moved)
	# Drop the player beside the car, then ask to enter it like a human would.
	var car := _car()
	if car == null:
		_failures.append("no Car node found in sandbox")
		_to_district()
		return
	_player().global_position = car.global_position + Vector3(2.0, 0.2, 0.0)
	_idle_engine_pitch = _engine_pitch(car)
	_next("approach_car")


func _phase_approach_car() -> void:
	if _frame == 10:
		_press_action_event("interact")
	if _frame < 20:
		return
	if _player().get("_vehicle") == null:
		_failures.append("interact near car did not enter it")
		_to_district()
		return
	print("playtest: entered car")
	Input.action_press("move_forward")
	_next("drive")


func _phase_drive() -> void:
	if _frame < DRIVE_FRAMES:
		return
	Input.action_release("move_forward")
	var car := _car()
	var speed: float = car.linear_velocity.length()
	var pitch := _engine_pitch(car)
	print(
		(
			"playtest: car at %.1f m/s after %d frames, engine pitch %.2f"
			% [speed, DRIVE_FRAMES, pitch]
		)
	)
	if speed < 3.0:
		_failures.append("car barely moved (%.1f m/s) — drivetrain broken" % speed)
	if pitch <= _idle_engine_pitch + 0.01:
		_failures.append(
			"engine pitch did not rise under throttle (%.2f -> %.2f)" % [_idle_engine_pitch, pitch]
		)
	_shot("sandbox_driving")
	_press_action_event("interact")
	_next("exit_car")


func _phase_exit_car() -> void:
	if _frame < 30:
		return
	if _player().get("_vehicle") != null:
		_failures.append("interact while driving did not exit the car")
	else:
		print("playtest: exited car")
	_to_district()


func _to_district() -> void:
	_next("district_load")
	change_scene_to_file("res://scenes/world/districts/downtown_la.tscn")


func _next(phase: String) -> void:
	_phase = phase
	_frame = 0


func _player() -> Node3D:
	return get_first_node_in_group("player") as Node3D


func _car() -> RigidBody3D:
	for node in get_nodes_in_group("vehicles"):
		if node is VehicleBody3D and node.name == "Car":
			return node
	return null


## Pitch of the car's synthesized engine loop (0.0 when audio is missing).
func _engine_pitch(car: Node3D) -> float:
	var audio := car.get_node_or_null("Audio")
	if audio == null:
		return 0.0
	for child in audio.get_children():
		var player := child as AudioStreamPlayer3D
		if player != null and player.playing:
			return player.pitch_scale
	return 0.0


## Route a press through the event pipeline so _unhandled_input handlers see it.
func _press_action_event(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	img.save_png(path)
	print("playtest: saved %s" % path)


func _finish() -> bool:
	if _failures.is_empty():
		print("playtest: OK")
	else:
		for f in _failures:
			push_error("playtest FAIL: " + f)
	quit(0 if _failures.is_empty() else 1)
	_phase = "done"
	return true
