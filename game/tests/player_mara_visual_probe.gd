extends SceneTree
## Diagnostic probe for Mara render captures. Reports visible meshes in the
## lower-body region so visual artifacts can be traced to a named node.

const PLAYER_SCENE := "res://scenes/player/player.tscn"

var _frames := 0
var _player: Node3D
var _camera: Camera3D
var _stabilized := false


func _initialize() -> void:
	var scene := load(PLAYER_SCENE) as PackedScene
	if scene == null:
		_fail("could not load player scene")
		return
	_player = scene.instantiate() as Node3D
	root.add_child(_player)
	_camera = Camera3D.new()
	_camera.name = "MaraVisualProbeCamera"
	_camera.look_at_from_position(Vector3(0.0, 1.12, 4.2), Vector3(0.0, 0.98, 0.0), Vector3.UP)
	root.add_child(_camera)
	_camera.make_current()


func _process(_delta: float) -> bool:
	_frames += 1
	if not _stabilized and _frames >= 3:
		_stabilize_player()
	if _frames < 24:
		return false
	_report_meshes(_player)
	quit(0)
	return true


func _stabilize_player() -> void:
	_stabilized = true
	_player.global_position = Vector3.ZERO
	_player.set_physics_process(false)
	var body := _player as CharacterBody3D
	if body != null:
		body.velocity = Vector3.ZERO
	var rig := _player.get_node_or_null("Rig")
	if rig != null and rig.has_method("animate"):
		for i in 40:
			rig.call("animate", Vector3.ZERO, true, 0.0, false, 1.0 / 60.0)


func _report_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.is_visible_in_tree():
			var bounds := mi.global_transform * mi.get_aabb()
			var center := bounds.get_center()
			var size := bounds.size
			if center.y < 0.35 or size.y > 0.7 or size.x > 0.5 or size.z > 0.5:
				print(
					"%s center=%s size=%s shadow=%s" % [mi.get_path(), center, size, mi.cast_shadow]
				)
	for child in node.get_children():
		_report_meshes(child)


func _fail(message: String) -> void:
	push_error("player_mara_visual_probe: %s" % message)
	quit(1)
