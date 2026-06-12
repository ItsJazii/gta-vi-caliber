extends SceneTree
## Headed QA capture for the animated player rig (issue #1): boots the
## playable map (miami — the repo's single world scene), simulates
## walk/sprint/jump input, asserts the AnimationTree is in the expected state
## at each phase, and saves screenshots for visual review.
## Needs a renderer — run WITHOUT --headless:
##   godot --path game --script res://tests/player_anim_capture.gd
## Screenshots land in /tmp/gta6_player_anim/. Not part of check.sh.

const OUT_DIR := "/tmp/gta6_player_anim"
const SETTLE_FRAMES := 90
const WALK_FRAMES := 100
const SPRINT_FRAMES := 100

var _frame := 0
var _phase := "boot"
var _phase_started_frame := 0
var _observed: Array[StringName] = []
var _steps := 0
var _steps_at_takeoff := -1
var _steps_at_enter := 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	change_scene_to_file("res://scenes/world/miami.tscn")


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		"boot":
			_phase_boot()
		"walk":
			_phase_walk()
		"sprint":
			_phase_sprint()
		"settle":
			_phase_settle()
		"jump":
			_phase_jump()
		"run_jump":
			_phase_run_jump()
		"front":
			_phase_front()
		"drive":
			_phase_drive()
		"exit_car":
			_phase_exit_car()
	return _phase == "done"


func _phase_boot() -> void:
	# Listen for footsteps from the first frame the player exists, so the
	# idle phase proves silence and the moving phases prove cadence.
	if _player() != null and not _player().is_connected("footstep", _count_step):
		_player().connect("footstep", _count_step)
	if _frame < SETTLE_FRAMES:
		return
	if _player() == null:
		_failures.append("no node in 'player' group after world boot")
		_finish()
		return
	_shot("01_idle")
	_expect_state(AnimRouter.STATE_MOVE, 0.0, 0.1, "idle")
	if _steps > 0:
		_failures.append("footsteps fired while standing idle (%d)" % _steps)
	Input.action_press("move_forward")
	_next("walk")


func _count_step(_surface: String, _is_left: bool) -> void:
	_steps += 1


func _phase_walk() -> void:
	if _frame < WALK_FRAMES:
		return
	_shot("02_walk")
	_expect_state(AnimRouter.STATE_MOVE, 0.5, 0.1, "walk")
	if _steps == 0:
		_failures.append("no footsteps while walking")
	print("capture: %d footsteps during walk phase" % _steps)
	Input.action_press("sprint")
	_next("sprint")


func _phase_sprint() -> void:
	if _frame < SPRINT_FRAMES:
		return
	_shot("03_sprint")
	_expect_state(AnimRouter.STATE_MOVE, 1.0, 0.1, "sprint")
	Input.action_release("move_forward")
	Input.action_release("sprint")
	_next("settle")


func _phase_settle() -> void:
	# Let the character brake to idle so the next jump is a standing jump.
	if _frame < 45:
		return
	Input.action_press("jump")
	_observed.clear()
	_next("jump")


## Standing jump: the full three-phase chain must play — JumpStart one-shot,
## Air loop, then the Land absorb (planar speed ~0 is under land_skip_speed).
func _phase_jump() -> void:
	if _frame == 5:
		Input.action_release("jump")
	_record_states("04_jump")
	if _frame > 600:
		_failures.append("standing jump never returned to Move (saw %s)" % str(_observed))
		_finish()
		return
	if _frame < 30 or not _grounded_in_move():
		return
	for expected: StringName in [
		AnimRouter.STATE_JUMP_START, AnimRouter.STATE_AIR, AnimRouter.STATE_LAND
	]:
		if not _observed.has(expected):
			_failures.append("standing jump skipped '%s' (saw %s)" % [expected, str(_observed)])
	print("capture: standing jump chain = %s" % str(_observed))
	Input.action_press("move_forward")
	Input.action_press("sprint")
	_observed.clear()
	_next("run_jump")


## Sprinting jump: landing above land_skip_speed must skip the Land absorb
## and roll straight back into locomotion.
func _phase_run_jump() -> void:
	if _frame == 60:
		Input.action_press("jump")
	if _frame == 65:
		Input.action_release("jump")
	if _frame <= 60:
		return
	_record_states("")
	if _frame > 600:
		_failures.append("running jump never returned to Move (saw %s)" % str(_observed))
		_finish()
		return
	if not _grounded_in_move() or _observed.is_empty():
		return
	if not _observed.has(AnimRouter.STATE_AIR):
		_failures.append("running jump never reached Air (saw %s)" % str(_observed))
	if _observed.has(AnimRouter.STATE_LAND):
		_failures.append("running landing should skip Land (saw %s)" % str(_observed))
	print("capture: running jump chain = %s" % str(_observed))
	Input.action_release("move_forward")
	Input.action_release("sprint")
	_next("front")


## Append each state-machine node as it becomes current; screenshot the
## airborne phases of the standing jump the first time each appears. Also
## police that no footstep fires while the body is off the ground.
func _record_states(shot_prefix: String) -> void:
	if not (_player() as CharacterBody3D).is_on_floor():
		if _steps_at_takeoff < 0:
			_steps_at_takeoff = _steps
		elif _steps != _steps_at_takeoff:
			_failures.append("footsteps fired mid-air")
			_steps_at_takeoff = _steps
	else:
		_steps_at_takeoff = -1
	var current := _current_state()
	if current == AnimRouter.STATE_MOVE:
		return
	if _observed.is_empty() or _observed[_observed.size() - 1] != current:
		_observed.append(current)
		if not shot_prefix.is_empty():
			_shot("%s_%s" % [shot_prefix, current])


func _grounded_in_move() -> bool:
	return (
		(_player() as CharacterBody3D).is_on_floor() and _current_state() == AnimRouter.STATE_MOVE
	)


func _phase_front() -> void:
	# Wait for the actual landing (frame rate varies, so counting frames
	# against the ~1 s jump arc is unreliable), then swing the camera around
	# to face the character so the model itself can be reviewed.
	if _phase_started_frame == 0:
		if (_player() as CharacterBody3D).is_on_floor():
			_phase_started_frame = _frame
			var camera_rig := _player().get_node("CameraRig") as Node3D
			camera_rig.rotation.y = PI
		elif _frame > 600:
			_failures.append("player never landed after jump")
			_finish()
		return
	if _frame < _phase_started_frame + 45:
		return
	_shot("05_front_idle")
	_expect_state(AnimRouter.STATE_MOVE, 0.0, 0.15, "front idle")
	var camera_rig := _player().get_node("CameraRig") as Node3D
	camera_rig.rotation.y = 0.0
	_next("drive")


## Driving regression check: the rig's AnimationTree stays active while the
## hidden player rides a vehicle, so no foot plants may leak through as
## footstep audio for the whole drive.
func _phase_drive() -> void:
	if _frame == 1:
		var car := _car()
		if car == null:
			_failures.append("no vehicle in the world for the drive check")
			_finish()
			return
		_player().global_position = car.global_position + Vector3(2.0, 0.2, 0.0)
	if _frame == 5:
		# Approach in motion: entering with a non-zero move blend is exactly
		# the case where a frozen rig would keep firing plants from the car.
		Input.action_press("move_forward")
	if _frame == 20:
		_press_action_event("interact")
	if _frame == 60:
		if _player().get("_vehicle") == null:
			_failures.append("interact near the car did not enter it")
			_finish()
			return
		# Baseline after entry: the move blend needs a beat to decay to idle.
		_steps_at_enter = _steps
	if _frame < 240:
		return
	Input.action_release("move_forward")
	if _steps != _steps_at_enter:
		_failures.append("footsteps fired while driving (%d)" % (_steps - _steps_at_enter))
	print("capture: drive phase silent (%d steps before, %d after)" % [_steps_at_enter, _steps])
	_press_action_event("interact")
	_next("exit_car")


func _phase_exit_car() -> void:
	if _frame < 30:
		return
	if _player().get("_vehicle") != null:
		_failures.append("interact while driving did not exit the car")
	_finish()


func _car() -> Node3D:
	for node in get_nodes_in_group("vehicles"):
		if node is VehicleBody3D and node.name == "Car":
			return node
	return null


## Route a press through the event pipeline so _unhandled_input handlers see it.
func _press_action_event(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


func _expect_state(node: StringName, blend: float, tolerance: float, label: String) -> void:
	var current := _current_state()
	if current != node:
		_failures.append("%s: expected state '%s', got '%s'" % [label, node, current])
	var actual_blend := _move_blend()
	if absf(actual_blend - blend) > tolerance:
		_failures.append("%s: expected blend ~%.2f, got %.2f" % [label, blend, actual_blend])
	print("capture: %s -> state=%s blend=%.2f" % [label, current, actual_blend])


func _current_state() -> StringName:
	var playback: AnimationNodeStateMachinePlayback = _tree().get("parameters/playback")
	return playback.get_current_node()


func _move_blend() -> float:
	return _tree().get("parameters/Move/blend_position")


func _tree() -> AnimationTree:
	return _player().get_node("Rig/AnimationTree") as AnimationTree


func _player() -> Node3D:
	return get_first_node_in_group("player") as Node3D


func _next(phase: String) -> void:
	_phase = phase
	_frame = 0
	_phase_started_frame = 0


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	img.save_png(path)
	print("capture: saved %s" % path)


func _finish() -> void:
	if _failures.is_empty():
		print("player anim capture: OK")
	else:
		for f in _failures:
			push_error("player anim capture FAIL: " + f)
	quit(0 if _failures.is_empty() else 1)
	_phase = "done"
