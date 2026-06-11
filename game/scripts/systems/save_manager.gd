class_name SaveManager
extends Node
## Quick-save (F5) / quick-load (F9) of game state.
##
## Gathers a snapshot from the player and the systems that own state (health,
## wanted) by group, serialises it via SaveData (pure, tested), and writes it to
## user://savegame.json. Uses raw key input so it adds no input actions, and
## finds everything by group so it needs no edits to the player scene. Player
## position, health, wanted level, and vehicle transform/health persist.

signal saved
signal loaded

const SAVE_PATH: String = "user://savegame.json"


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F5:
		save_game()
	elif key.keycode == KEY_F9:
		load_game()


func save_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(SaveData.encode(_gather()))
	saved.emit()


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	_apply(SaveData.decode(file.get_as_text()))
	loaded.emit()


func _gather() -> Dictionary:
	var snapshot: Dictionary = {}
	var player := _player()
	if player != null:
		snapshot["player_pos"] = SaveData.vec3_to_array(player.global_position)
	snapshot["vehicles"] = _gather_vehicles()
	var health := _first("player_health")
	if health != null and health.has_method("serialize"):
		snapshot["health"] = health.serialize()
	var wanted := _first("wanted")
	if wanted != null and wanted.has_method("serialize"):
		snapshot["wanted"] = wanted.serialize()
	return snapshot


func _apply(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	var player := _player()
	if player != null and player.has_method("eject"):
		player.eject()
	_apply_vehicles(snapshot.get("vehicles", {}))
	if player != null and snapshot.has("player_pos"):
		player.global_position = SaveData.array_to_vec3(
			snapshot["player_pos"], player.global_position
		)
		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity = Vector3.ZERO
	var health := _first("player_health")
	if health != null and health.has_method("restore"):
		health.restore(snapshot.get("health", {}))
	var wanted := _first("wanted")
	if wanted != null and wanted.has_method("restore"):
		wanted.restore(snapshot.get("wanted", {}))


func _player() -> Node3D:
	return _first("player") as Node3D


func _gather_vehicles() -> Dictionary:
	var vehicles: Dictionary = {}
	for node in get_tree().get_nodes_in_group("vehicles"):
		var car := node as Car
		if car == null:
			continue
		vehicles[car.name] = {
			"transform": SaveData.transform_to_dict(car.global_transform),
			"health": car.health,
		}
	return vehicles


func _apply_vehicles(snapshot: Variant) -> void:
	if not snapshot is Dictionary:
		return
	var vehicles: Dictionary = snapshot
	for node in get_tree().get_nodes_in_group("vehicles"):
		var car := node as Car
		if car == null or not vehicles.has(car.name):
			continue
		var data: Variant = vehicles[car.name]
		if not data is Dictionary:
			continue
		var vehicle_data: Dictionary = data
		car.global_transform = SaveData.dict_to_transform(
			vehicle_data.get("transform"), car.global_transform
		)
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		car.health = clampf(
			SaveData.number_or(vehicle_data.get("health"), car.health), 0.0, car.max_health
		)


func _first(group: String) -> Node:
	var nodes := get_tree().get_nodes_in_group(group)
	return nodes[0] if not nodes.is_empty() else null
