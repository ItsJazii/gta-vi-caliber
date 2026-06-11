extends SceneTree
## Runtime guard for the playable Mara integration. This catches lifecycle bugs
## that unit tests cannot see, such as deferred GLB attachment under the wrong
## part of the animated rig.

const PLAYER_SCENE := "res://scenes/player/player.tscn"

var _frames := 0
var _player: Node
var _camera: Camera3D
var _imported: Node3D = null
var _torso: MeshInstance3D = null
var _checked_front := false
var _checked_front_side := false
var _checked_rear := false


func _initialize() -> void:
	var scene := load(PLAYER_SCENE) as PackedScene
	if scene == null:
		_fail("could not load player scene")
		return
	_player = scene.instantiate()
	root.add_child(_player)
	_camera = Camera3D.new()
	_camera.name = "MaraRuntimeCamera"
	root.add_child(_camera)
	_camera.look_at_from_position(Vector3(0.0, 1.12, -4.2), Vector3(0.0, 0.98, 0.0), Vector3.UP)
	_camera.make_current()


func _process(_delta: float) -> bool:
	_frames += 1
	var done := false
	if _frames < 3:
		pass
	elif not _checked_front:
		done = not _check_front_view()
		if not done:
			_checked_front = true
			_camera.look_at_from_position(
				Vector3(4.2, 1.12, 0.0), Vector3(0.0, 0.98, 0.0), Vector3.UP
			)
			_camera.make_current()
	elif _frames < 8:
		pass
	elif not _checked_front_side:
		done = not _check_front_side_hysteresis()
		if not done:
			_checked_front_side = true
			_camera.look_at_from_position(
				Vector3(0.0, 1.12, 4.2), Vector3(0.0, 0.98, 0.0), Vector3.UP
			)
			_camera.make_current()
	elif _frames < 13:
		pass
	elif not _checked_rear:
		done = not _check_rear_view()
		if not done:
			_checked_rear = true
			_camera.look_at_from_position(
				Vector3(4.2, 1.12, 0.0), Vector3(0.0, 0.98, 0.0), Vector3.UP
			)
			_camera.make_current()
	elif _frames < 18:
		pass
	elif not _check_rear_side_hysteresis():
		done = true
	else:
		done = _check_animated_attachment()
	return done


func _check_animated_attachment() -> bool:
	var hips := _player.get_node_or_null("Rig/Hips") as Node3D
	var head := _player.get_node_or_null("Rig/Hips/Head") as Node3D
	var pelvis := _player.get_node_or_null("Rig/Hips/Pelvis") as Node3D
	var torso := _player.get_node_or_null("Rig/Hips/Torso") as Node3D
	var shoulder_l := _player.get_node_or_null("Rig/Hips/ShoulderL") as Node3D
	var body := _player.get_node_or_null("Rig/Body")
	var rig := _player.get_node_or_null("Rig") as CharacterAnimator
	if (
		hips == null
		or head == null
		or pelvis == null
		or torso == null
		or shoulder_l == null
		or body == null
		or rig == null
	):
		_fail("player rig hierarchy is incomplete")
		return true
	var before_y := _imported.global_position.y
	rig.animate(Vector3(5.0, 0.0, 0.0), true, 0.0, false, 0.1)
	if not _check_after_animated_motion(before_y, body, pelvis, torso, shoulder_l, head):
		return true
	print("player_mara_runtime: OK")
	quit(0)
	return true


func _check_after_animated_motion(
	before_y: float, body: Node, pelvis: Node3D, torso: Node3D, shoulder_l: Node3D, head: Node3D
) -> bool:
	if is_equal_approx(_imported.global_position.y, before_y):
		_fail("imported Mara mesh did not inherit animated hip motion")
		return false
	if not _check_secondary_motion(pelvis, torso, shoulder_l, head):
		return false
	if not _check_mara_soft_motion(body):
		return false
	if not _check_mara_rounded_gear():
		return false
	if not _check_face_life(body):
		return false
	return _check_mara_material_quality()


func _check_secondary_motion(
	pelvis: Node3D, torso: Node3D, shoulder_l: Node3D, head: Node3D
) -> bool:
	if is_zero_approx(absf(head.rotation.x) + absf(head.rotation.z)):
		_fail("playable Mara head did not receive secondary motion")
		return false
	return _check_stride_twist(pelvis, torso, shoulder_l, head)


func _check_stride_twist(pelvis: Node3D, torso: Node3D, shoulder_l: Node3D, head: Node3D) -> bool:
	var twist_strength := (
		absf(torso.rotation.y)
		+ absf(shoulder_l.rotation.y)
		+ absf(pelvis.rotation.y)
		+ absf(head.rotation.y)
	)
	if twist_strength > 0.001 and signf(torso.rotation.y) == signf(shoulder_l.rotation.y):
		return true
	_fail("playable Mara stride did not apply upper-body twist")
	return false


func _check_mara_soft_motion(body: Node) -> bool:
	var pendant := _player.get_node_or_null("Rig/Hips/MaraPendant") as Node3D
	var strap := _player.get_node_or_null("Rig/Hips/MaraMessengerStrap") as Node3D
	var hair := _player.get_node_or_null("Rig/Hips/Head/MaraRearHairMass") as Node3D
	if pendant == null or strap == null or hair == null:
		_fail("playable Mara soft-motion nodes are missing")
		return false
	if (
		not pendant.get_meta("mara_soft_motion", false)
		or not strap.get_meta("mara_soft_motion", false)
	):
		_fail("playable Mara gear is not marked for soft motion")
		return false
	var before_position := pendant.position
	var before_rotation := strap.rotation
	body.call("_process", 0.1)
	var pendant_moved := pendant.position.distance_to(before_position) > 0.0001
	var strap_rotated := strap.rotation.distance_to(before_rotation) > 0.0001
	if pendant_moved and strap_rotated and hair.get_meta("mara_soft_motion", false):
		return true
	_fail("playable Mara soft-motion gear did not react to stride")
	return false


func _check_mara_rounded_gear() -> bool:
	var strap := _player.get_node_or_null("Rig/Hips/MaraMessengerStrap") as MeshInstance3D
	var rear_strap := _player.get_node_or_null("Rig/Hips/MaraMessengerStrapBack") as MeshInstance3D
	var cord := _player.get_node_or_null("Rig/Hips/MaraPendantCord") as MeshInstance3D
	if strap == null or rear_strap == null or cord == null:
		_fail("playable Mara rounded gear nodes are missing")
		return false
	if strap.mesh is BoxMesh or rear_strap.mesh is BoxMesh or cord.mesh is BoxMesh:
		_fail("playable Mara key straps still use blocky box meshes")
		return false
	return true


func _check_front_view() -> bool:
	_camera.make_current()
	_imported = _player.get_node_or_null("Rig/Hips/MaraImportedMesh") as Node3D
	if _imported == null:
		_fail("MaraImportedMesh was not attached under Rig/Hips")
		return false
	if not _has_visible_mesh(_imported):
		_fail("front camera did not show imported Mara mesh")
		return false
	if not _imported_casts_shadows():
		_fail("front camera did not enable imported Mara shadows")
		return false
	_torso = _player.get_node_or_null("Rig/Hips/Torso") as MeshInstance3D
	if _torso != null and _torso.visible:
		_fail("procedural body is still visible over imported Mara front mesh")
		return false
	return true


func _check_front_side_hysteresis() -> bool:
	_camera.make_current()
	if _imported != null and not _has_visible_mesh(_imported):
		_fail("side camera lost imported Mara before rear threshold")
		return false
	if _torso != null and _torso.visible:
		_fail("side camera restored procedural body before rear threshold")
		return false
	return true


func _check_rear_view() -> bool:
	_camera.make_current()
	if not _check_rear_mesh_switch():
		return false
	if not _has_full_body_mara_gear():
		_fail("rear gameplay Mara rig is missing full-body hero gear")
		return false
	if not _check_procedural_shadow_budget():
		return false
	return _check_procedural_cosmetic_lod()


func _check_rear_mesh_switch() -> bool:
	if _imported != null and _has_visible_mesh(_imported):
		_fail("rear gameplay camera still shows imported Mara rear shell")
		return false
	if _imported_casts_shadows():
		_fail("rear gameplay camera still lets hidden imported Mara cast shadows")
		return false
	if _torso != null and not _torso.visible:
		_fail("rear gameplay camera did not restore procedural Mara body")
		return false
	return true


func _check_rear_side_hysteresis() -> bool:
	_camera.make_current()
	if _imported != null and _has_visible_mesh(_imported):
		_fail("side camera re-shown imported Mara before front threshold")
		return false
	if _torso != null and not _torso.visible:
		_fail("side camera hid procedural body before front threshold")
		return false
	return true


func _fail(message: String) -> void:
	push_error("player_mara_runtime: %s" % message)
	quit(1)


func _has_visible_mesh(node: Node) -> bool:
	if node is MeshInstance3D and (node as MeshInstance3D).is_visible_in_tree():
		return true
	for child in node.get_children():
		if _has_visible_mesh(child):
			return true
	return false


func _imported_casts_shadows() -> bool:
	return _has_shadow_casting_mesh(_imported)


func _has_shadow_casting_mesh(node: Node) -> bool:
	if node == null:
		return false
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			return true
	for child in node.get_children():
		if _has_shadow_casting_mesh(child):
			return true
	return false


func _has_full_body_mara_gear() -> bool:
	var required: PackedStringArray = [
		"Rig/Hips/MaraSideHolster",
		"Rig/Hips/HipL/MaraThighUtilityBand",
		"Rig/Hips/HipR/MaraKneePad",
		"Rig/Hips/HipL/Knee/Ankle/MaraBootSole",
		"Rig/Hips/ShoulderL/Elbow/MaraWristWrap",
		"Rig/Hips/ShoulderR/Elbow/MaraGloveKnuckles",
		"Rig/Hips/Head/MaraSideHairLock",
		"Rig/Hips/Head/MaraBlinkLid",
	]
	for path in required:
		if _player.get_node_or_null(path) == null:
			return false
	return true


func _check_face_life(body: Node) -> bool:
	var lid := _player.get_node_or_null("Rig/Hips/Head/MaraBlinkLid") as MeshInstance3D
	if lid == null:
		_fail("playable Mara face is missing blink eyelids")
		return false
	body.set("_blink_t", 0.0)
	var before := lid.scale.y
	body.call("_process", 0.08)
	if is_equal_approx(lid.scale.y, before):
		_fail("playable Mara blink eyelids did not animate")
		return false
	return true


func _check_mara_material_quality() -> bool:
	var head := _player.get_node_or_null("Rig/Hips/Head") as MeshInstance3D
	var jacket := _player.get_node_or_null("Rig/Hips/MaraCroppedJacket") as MeshInstance3D
	var strap := _player.get_node_or_null("Rig/Hips/MaraMessengerStrap") as MeshInstance3D
	var hair := _player.get_node_or_null("Rig/Hips/Head/MaraRearHairMass") as MeshInstance3D
	if head == null or jacket == null or strap == null or hair == null:
		_fail("playable Mara material-quality nodes are missing")
		return false
	var skin := head.material_override as StandardMaterial3D
	var jacket_mat := jacket.material_override as StandardMaterial3D
	var strap_mat := strap.material_override as StandardMaterial3D
	var hair_mat := hair.material_override as StandardMaterial3D
	if skin == null or jacket_mat == null or strap_mat == null or hair_mat == null:
		_fail("playable Mara material-quality surfaces are missing")
		return false
	return (
		_check_skin_material(skin)
		and _check_jacket_material(jacket_mat)
		and _check_leather_material(strap_mat)
		and _check_hair_material(hair_mat)
	)


func _check_skin_material(mat: StandardMaterial3D) -> bool:
	if mat.subsurf_scatter_enabled and mat.clearcoat_enabled and mat.normal_enabled:
		return true
	_fail("playable Mara skin material is missing premium skin shading")
	return false


func _check_jacket_material(mat: StandardMaterial3D) -> bool:
	if mat.normal_enabled and mat.uv1_triplanar:
		return true
	_fail("playable Mara jacket material is missing triplanar fabric detail")
	return false


func _check_leather_material(mat: StandardMaterial3D) -> bool:
	if mat.clearcoat_enabled and mat.normal_enabled and mat.uv1_triplanar:
		return true
	_fail("playable Mara leather material is missing worn-sheen detail")
	return false


func _check_hair_material(mat: StandardMaterial3D) -> bool:
	if mat.rim_enabled and String(mat.get_meta("mara_surface_profile", "")) == "hair":
		return true
	_fail("playable Mara hair material is missing silhouette shading")
	return false


func _check_procedural_shadow_budget() -> bool:
	var torso := _player.get_node_or_null("Rig/Hips/Torso") as MeshInstance3D
	var strap := _player.get_node_or_null("Rig/Hips/MaraMessengerStrap") as MeshInstance3D
	var eyelid := _player.get_node_or_null("Rig/Hips/Head/MaraBlinkLid") as MeshInstance3D
	if torso == null or strap == null or eyelid == null:
		_fail("playable Mara shadow-budget nodes are missing")
		return false
	if torso.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_fail("main playable Mara body shadow was disabled")
		return false
	if strap.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_fail("playable Mara cosmetic strap still casts shadows")
		return false
	if eyelid.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_fail("playable Mara blink eyelid still casts shadows")
		return false
	return true


func _check_procedural_cosmetic_lod() -> bool:
	var body := _player.get_node_or_null("Rig/Body")
	var torso := _player.get_node_or_null("Rig/Hips/Torso") as MeshInstance3D
	var strap := _player.get_node_or_null("Rig/Hips/MaraMessengerStrap") as MeshInstance3D
	if body == null or torso == null or strap == null:
		_fail("playable Mara cosmetic LOD nodes are missing")
		return false
	if not strap.visible:
		_fail("playable Mara close cosmetic detail was hidden")
		return false
	_camera.look_at_from_position(Vector3(0.0, 1.12, 32.0), Vector3(0.0, 0.98, 0.0), Vector3.UP)
	_camera.make_current()
	body.call("_process", 0.016)
	if not torso.visible:
		_fail("playable Mara main body was hidden by cosmetic LOD")
		return false
	if strap.visible:
		_fail("playable Mara far cosmetic detail stayed visible")
		return false
	_camera.look_at_from_position(Vector3(0.0, 1.12, 4.2), Vector3(0.0, 0.98, 0.0), Vector3.UP)
	_camera.make_current()
	body.call("_process", 0.016)
	if not strap.visible:
		_fail("playable Mara close cosmetic detail was not restored")
		return false
	return true
