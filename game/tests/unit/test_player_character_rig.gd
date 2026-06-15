extends RefCounted
## Guards the playable hero scene wiring: the player must boot with the merged
## Meshy MC visual driven by McPlayerRig, while keeping the phone pose hook,
## foot-plant signal, and weapon gun-mount contracts.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const RIG_SCENE := "res://scenes/player/mc_rig.tscn"
const PLAYER_VISUAL := "res://assets/characters/mc/mc_shirtless_full_anims.glb"
const LEATHER_TEX := "res://assets/textures/leather.png"


class MockRepairableVehicle:
	extends Node3D
	var health: float = 25.0
	var max_health: float = 100.0


class MockUnrepairableVehicle:
	extends Node3D


func test_player_uses_meshy_rig() -> bool:
	var player := _player_instance()
	if player == null:
		return false
	var rig := player.get_node_or_null("Rig")
	var ok: bool = rig is McPlayerRig and rig.scene_file_path == RIG_SCENE
	player.free()
	return ok


func test_player_uses_merged_mc_visual() -> bool:
	var player := _player_instance()
	if player == null:
		return false
	var rig := player.get_node_or_null("Rig")
	if rig == null:
		player.free()
		return false
	var model := rig.get_node_or_null("Model")
	var ok: bool = model != null and model.scene_file_path == PLAYER_VISUAL
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


func test_player_mechanic_service_repairs_current_vehicle() -> bool:
	var player := _player_instance() as Player
	if player == null:
		return false
	var vehicle := MockRepairableVehicle.new()
	player.set("_vehicle", vehicle)
	var ok := (
		player.service_current_vehicle() and is_equal_approx(vehicle.health, vehicle.max_health)
	)
	vehicle.free()
	player.free()
	return ok


func test_player_mechanic_service_noops_without_repairable_vehicle() -> bool:
	var player := _player_instance() as Player
	if player == null:
		return false
	var empty := player.service_current_vehicle()
	var vehicle := MockUnrepairableVehicle.new()
	player.set("_vehicle", vehicle)
	var unrepairable := player.service_current_vehicle()
	vehicle.free()
	player.free()
	return not empty and not unrepairable


func _player_instance() -> Node:
	var scene := load(PLAYER_SCENE) as PackedScene
	if scene == null:
		return null
	return scene.instantiate()
