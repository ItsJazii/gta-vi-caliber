extends RefCounted
## Guards the playable hero scene wiring: the player must boot with the
## skeletal character rig (AnimatedRig on the Quaternius base character,
## issue #1) and keep the contracts its siblings rely on — the phone pose
## hook, the foot-plant footstep signal, and the weapon gun mount.
##
## Successor to test_player_mara_character.gd: the Mara proxy rode the
## procedural HumanoidBody, which the player scene no longer instantiates.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const RIG_SCENE := "res://scenes/player/character_rig.tscn"
const LEATHER_TEX := "res://assets/textures/leather.png"


func test_player_uses_animated_rig() -> bool:
	var player := _player_instance()
	if player == null:
		return false
	var rig := player.get_node_or_null("Rig")
	var ok: bool = rig is AnimatedRig and rig.scene_file_path == RIG_SCENE
	player.free()
	return ok


func test_player_rig_keeps_phone_contract() -> bool:
	var player := _player_instance()
	if player == null:
		return false
	var rig := player.get_node_or_null("Rig")
	var ok: bool = (
		rig != null
		and rig.has_method("set_phone")
		and rig.has_method("animate")
		and rig.has_signal("foot_planted")
	)
	player.free()
	return ok


func test_player_keeps_weapon_gun_mount() -> bool:
	var player := _player_instance()
	if player == null:
		return false
	var mount := player.get_node_or_null("Rig/GunMount")
	var muzzle := player.get_node_or_null("Rig/GunMount/Muzzle")
	var weapons := player.get_node_or_null("WeaponController")
	var ok: bool = mount != null and muzzle != null and weapons != null
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


func test_player_has_ledgered_leather_texture() -> bool:
	return load(LEATHER_TEX) is Texture2D


func _player_instance() -> Node:
	var scene := load(PLAYER_SCENE) as PackedScene
	if scene == null:
		return null
	return scene.instantiate()
