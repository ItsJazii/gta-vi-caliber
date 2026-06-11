extends SceneTree
## Headed visual check for the ocean: boots ocean_demo, parks a camera on
## the beach looking into the sun glitter, waits for the sea to settle and
## saves a screenshot. Must run with a window (no --headless):
##   godot --path game --resolution 1280x720 --script res://tests/ocean_capture.gd

const SCENE_PATH := "res://scenes/world/ocean_demo.tscn"
const OUTPUT_PATH := "/tmp/ocean_demo.png"
const SETTLE_FRAMES := 90

var _frames: int = 0
var _camera: Camera3D


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	root.add_child(packed.instantiate())
	_camera = Camera3D.new()
	_camera.fov = 70.0
	root.add_child(_camera)
	_camera.look_at_from_position(Vector3(0.0, 12.0, 505.0), Vector3(0.0, -5.0, 420.0))


func _process(_delta: float) -> bool:
	_frames += 1
	_camera.current = true  # outrank the player camera every frame
	if _frames < SETTLE_FRAMES:
		return false
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(OUTPUT_PATH)
	print("ocean capture: saved %s" % OUTPUT_PATH)
	quit(0)
	return true
