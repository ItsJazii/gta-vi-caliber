extends SceneTree
## Runtime guard for the actual player OrbitCamera inspection mode. This proves
## the in-game camera, not just a test camera, can bring Mara's textured front
## mesh into view and return to gameplay framing.

const PLAYER_SCENE := "res://scenes/player/player.tscn"

var _frames := 0
var _player: Node
var _camera_rig: OrbitCamera
var _imported: Node3D
var _inspect_light: SpotLight3D
var _inspect_rim_light: OmniLight3D
var _initial_yaw := 0.0
var _initial_gameplay_yaw := 0.0
var _started_inspect := false
var _released_inspect := false


func _initialize() -> void:
	var scene := load(PLAYER_SCENE) as PackedScene
	if scene == null:
		_fail("could not load player scene")
		return
	_player = scene.instantiate()
	root.add_child(_player)
	_camera_rig = _player.get_node_or_null("CameraRig") as OrbitCamera
	_imported = _player.get_node_or_null("Rig/Hips/MaraImportedMesh") as Node3D


func _process(_delta: float) -> bool:
	_frames += 1
	var done := false
	if _frames < 4:
		pass
	elif _camera_rig == null:
		_fail("player CameraRig is missing")
		done = true
	elif _imported == null:
		_imported = _player.get_node_or_null("Rig/Hips/MaraImportedMesh") as Node3D
		if _imported == null:
			_fail("MaraImportedMesh was not attached")
			done = true
	elif not _started_inspect:
		_initial_yaw = _camera_rig.rotation.y
		_initial_gameplay_yaw = _camera_rig.gameplay_yaw()
		_camera_rig.set_character_inspect(true)
		_camera_rig.make_current()
		_started_inspect = true
	elif _frames < 80:
		pass
	elif not _released_inspect:
		done = not _check_inspection_view()
		if not done:
			_camera_rig.set_character_inspect(false)
			_released_inspect = true
	elif _frames < 140:
		pass
	else:
		done = _check_returned_view()
	return done


func _check_inspection_view() -> bool:
	if not _has_visible_mesh(_imported):
		_fail("player inspect camera did not reveal Mara's imported front mesh")
		return false
	if absf(wrapf(_camera_rig.rotation.y - PI, -PI, PI)) > 0.12:
		_fail("player inspect camera did not rotate to front view")
		return false
	if absf(wrapf(_camera_rig.gameplay_yaw() - _initial_gameplay_yaw, -PI, PI)) > 0.01:
		_fail("player inspect camera changed gameplay movement yaw")
		return false
	_resolve_inspect_light()
	if _inspect_light == null or not _inspect_light.visible or _inspect_light.shadow_enabled:
		_fail("player inspect camera did not enable shadowless character fill light")
		return false
	if (
		_inspect_rim_light == null
		or not _inspect_rim_light.visible
		or _inspect_rim_light.shadow_enabled
	):
		_fail("player inspect camera did not enable shadowless character rim light")
		return false
	return true


func _check_returned_view() -> bool:
	if absf(wrapf(_camera_rig.rotation.y - _initial_yaw, -PI, PI)) > 0.12:
		_fail("player inspect camera did not return to gameplay yaw")
		return true
	if absf(wrapf(_camera_rig.gameplay_yaw() - _initial_gameplay_yaw, -PI, PI)) > 0.01:
		_fail("player inspect camera did not preserve gameplay movement yaw")
		return true
	_resolve_inspect_light()
	if _inspect_light != null and _inspect_light.visible:
		_fail("player inspect camera left character fill light enabled")
		return true
	if _inspect_rim_light != null and _inspect_rim_light.visible:
		_fail("player inspect camera left character rim light enabled")
		return true
	print("player_mara_camera_runtime: OK")
	quit(0)
	return true


func _fail(message: String) -> void:
	push_error("player_mara_camera_runtime: %s" % message)
	quit(1)


func _resolve_inspect_light() -> void:
	if _inspect_light == null:
		_inspect_light = (
			_player.get_node_or_null("CameraRig/SpringArm/Camera/CharacterInspectLight")
			as SpotLight3D
		)
	if _inspect_rim_light == null:
		_inspect_rim_light = (
			_player.get_node_or_null("CameraRig/SpringArm/Camera/CharacterInspectRimLight")
			as OmniLight3D
		)


func _has_visible_mesh(node: Node) -> bool:
	if node is MeshInstance3D and (node as MeshInstance3D).is_visible_in_tree():
		return true
	for child in node.get_children():
		if _has_visible_mesh(child):
			return true
	return false
