extends RefCounted
## Guards the playable hero scene wiring for Mara: the player must boot with
## the Mara profile enabled and a real imported character mesh attached.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const MARA_MESH := "res://assets/characters/char_textured.glb"
const LEATHER_TEX := "res://assets/textures/leather.png"


func test_player_uses_mara_profile() -> bool:
	var player := _player_instance()
	if player == null:
		return false
	var body := player.get_node_or_null("Rig/Body")
	var ok: bool = body != null and body.get("use_mara_hero_profile") == true
	player.free()
	return ok


func test_player_has_imported_mara_mesh() -> bool:
	var player := _player_instance()
	if player == null:
		return false
	var body := player.get_node_or_null("Rig/Body")
	if body == null:
		player.free()
		return false
	var imported := body.get("imported_mara_scene") as PackedScene
	var ok: bool = imported != null and imported.resource_path == MARA_MESH
	player.free()
	return ok


func test_player_mara_mesh_uses_hips_relative_offset() -> bool:
	var player := _player_instance()
	if player == null:
		return false
	var body := player.get_node_or_null("Rig/Body")
	if body == null:
		player.free()
		return false
	var ok: bool = body.get("imported_mara_offset") == Vector3(0.0, 0.075, 0.0)
	player.free()
	return ok


func test_player_hides_procedural_body_when_imported_mara_is_present() -> bool:
	var player := _player_instance()
	if player == null:
		return false
	var body := player.get_node_or_null("Rig/Body")
	if body == null:
		player.free()
		return false
	var ok: bool = body.get("hide_procedural_when_imported") == true
	player.free()
	return ok


func test_player_switches_mara_mesh_by_camera_angle() -> bool:
	var player := _player_instance()
	if player == null:
		return false
	var body := player.get_node_or_null("Rig/Body")
	if body == null:
		player.free()
		return false
	var ok: bool = body.get("switch_imported_mara_by_camera") == true
	player.free()
	return ok


func test_player_mara_camera_switch_has_hysteresis() -> bool:
	var player := _player_instance()
	if player == null:
		return false
	var body := player.get_node_or_null("Rig/Body")
	if body == null:
		player.free()
		return false
	var front_dot := float(body.get("imported_mara_front_dot"))
	var rear_dot := float(body.get("imported_mara_rear_dot"))
	var ok: bool = rear_dot < 0.0 and front_dot > 0.0 and rear_dot < front_dot
	player.free()
	return ok


func test_player_camera_supports_character_inspection() -> bool:
	var player := _player_instance()
	if player == null:
		return false
	var camera := player.get_node_or_null("CameraRig")
	if camera == null:
		player.free()
		return false
	var ok: bool = (
		camera.has_method("set_character_inspect")
		and camera.has_method("gameplay_yaw")
		and float(camera.get("inspect_fov")) < float(camera.get("base_fov"))
		and is_equal_approx(float(camera.get("inspect_yaw")), PI)
		and float(camera.get("inspect_light_energy")) > 0.0
		and float(camera.get("inspect_rim_light_energy")) > 0.0
	)
	player.free()
	return ok


func test_player_animator_has_secondary_motion() -> bool:
	var player := _player_instance()
	if player == null:
		return false
	var rig := player.get_node_or_null("Rig")
	var ok: bool = (
		rig != null
		and float(rig.get("sway_amplitude")) > 0.0
		and float(rig.get("roll_amplitude")) > 0.0
		and float(rig.get("head_pitch_amplitude")) > 0.0
		and float(rig.get("head_roll_amplitude")) > 0.0
	)
	player.free()
	return ok


func test_player_body_has_face_life() -> bool:
	var player := _player_instance()
	if player == null:
		return false
	var body := player.get_node_or_null("Rig/Body")
	var ok: bool = body != null and body.has_method("_process")
	player.free()
	return ok


func test_player_has_ledgered_leather_texture() -> bool:
	return load(LEATHER_TEX) is Texture2D


func test_player_has_cosmetic_lod_budget() -> bool:
	var player := _player_instance()
	if player == null:
		return false
	var body := player.get_node_or_null("Rig/Body")
	var ok: bool = body != null and float(body.get("cosmetic_lod_distance")) > 0.0
	player.free()
	return ok


func _player_instance() -> Node:
	var scene := load(PLAYER_SCENE) as PackedScene
	if scene == null:
		return null
	return scene.instantiate()
