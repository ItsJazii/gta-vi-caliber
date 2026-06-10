extends SceneTree
## Headed QA playtest: boots real scenes, simulates input, asserts the player
## actually moves, and saves screenshots for visual review. Needs a renderer —
## run WITHOUT --headless:
##   godot --path game --script res://tests/playtest_capture.gd
## Screenshots land in /tmp/gta6_playtest/. Not part of check.sh (CI is headless).

const OUT_DIR := "/tmp/gta6_playtest"
const WALK_FRAMES := 180

var _frame := 0
var _phase := "boot"
var _start_pos := Vector3.ZERO
var _failures: PackedStringArray = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	change_scene_to_file("res://scenes/world/sandbox.tscn")


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		"boot":
			if _frame >= 60:
				_shot("sandbox_idle")
				var player := _player()
				if player == null:
					_failures.append("no node in 'player' group after sandbox boot")
					return _finish()
				_start_pos = player.global_position
				Input.action_press("move_forward")
				_phase = "walk"
				_frame = 0
		"walk":
			if _frame >= WALK_FRAMES:
				Input.action_release("move_forward")
				_shot("sandbox_walked")
				var player := _player()
				var moved := player.global_position.distance_to(_start_pos)
				print("playtest: player walked %.2f m in %d frames" % [moved, WALK_FRAMES])
				if moved < 2.0:
					_failures.append(
						"player barely moved (%.2f m) — input/locomotion broken" % moved
					)
				_phase = "district_load"
				_frame = 0
				change_scene_to_file("res://scenes/world/districts/downtown_la.tscn")
		"district_load":
			# District has no spawn logic guarantee; just let it build + render.
			if _frame >= 120:
				_shot("district_downtown")
				return _finish()
	return false


func _player() -> Node3D:
	return get_first_node_in_group("player") as Node3D


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
	return true
