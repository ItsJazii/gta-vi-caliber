class_name SaveManager
extends Node
## Quick-save ("quick_save", F5) / quick-load ("quick_load", F9) of game state.
##
## Gathers a snapshot from the player and the systems that own state (health,
## wanted, stats, progression, properties) by group, serialises it via SaveData
## (pure, tested, versioned with migration), and writes it to
## user://savegame.json. Finds everything by group so it needs no edits to the
## player scene. Player position, health, wanted level, money/armor, respect
## XP, property ownership, and every vehicle's transform (+health where the
## vehicle has one — cars and bikes; boats are transform-only) persist.
## Vehicles are found through the "vehicles" group and matched by node name
## (unique within a scene), so this stays streaming-ready.

signal saved
signal loaded

const SAVE_PATH: String = "user://savegame.json"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quick_save"):
		save_game()
	elif event.is_action_pressed("quick_load"):
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
	var text := file.get_as_text()
	_apply(SaveData.migrate(SaveData.decode(text), SaveData.version_of(text)))
	loaded.emit()


func _gather() -> Dictionary:
	var snapshot: Dictionary = {}
	var player := _player()
	if player != null:
		var pos := player.global_position
		snapshot["player_pos"] = [pos.x, pos.y, pos.z]
	for entry in [
		["health", "player_health"],
		["wanted", "wanted"],
		["stats", "player_stats"],
		["progression", "progression"],
	]:
		var holder := _first(entry[1])
		if holder != null and holder.has_method("serialize"):
			snapshot[entry[0]] = holder.serialize()
	snapshot["properties"] = _gather_properties()
	snapshot["vehicles"] = _gather_vehicles()
	return snapshot


## One entry per PropertyHub, keyed by node name (unique within the scene).
func _gather_properties() -> Dictionary:
	var hubs: Dictionary = {}
	for hub in get_tree().get_nodes_in_group("property_hub"):
		if hub.has_method("serialize"):
			hubs[String(hub.name)] = hub.serialize()
	return hubs


func _gather_vehicles() -> Dictionary:
	var vehicles: Dictionary = {}
	for node in get_tree().get_nodes_in_group("vehicles"):
		var vehicle := node as Node3D
		if vehicle == null:
			continue
		var entry := {"transform": SaveData.transform_to_dict(vehicle.global_transform)}
		if "health" in vehicle:
			entry["health"] = vehicle.health
		vehicles[String(vehicle.name)] = entry
	return vehicles


func _apply(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	var player := _player()
	if player != null and snapshot.has("player_pos"):
		var values: Array = snapshot["player_pos"]
		if values.size() == 3:
			if player.has_method("eject"):
				player.call("eject")
			player.global_position = Vector3(values[0], values[1], values[2])
			if player is CharacterBody3D:
				(player as CharacterBody3D).velocity = Vector3.ZERO
	for entry in [
		["health", "player_health"],
		["wanted", "wanted"],
		["stats", "player_stats"],
		["progression", "progression"],
	]:
		var holder := _first(entry[1])
		if holder != null and holder.has_method("restore"):
			holder.restore(snapshot.get(entry[0], {}))
	if snapshot.get("properties") is Dictionary:
		_apply_properties(snapshot["properties"])
	if snapshot.get("vehicles") is Dictionary:
		_apply_vehicles(snapshot["vehicles"])


func _apply_properties(data: Dictionary) -> void:
	for hub in get_tree().get_nodes_in_group("property_hub"):
		if hub.has_method("restore") and data.get(String(hub.name)) is Dictionary:
			hub.restore(data[String(hub.name)])


func _apply_vehicles(data: Dictionary) -> void:
	for node in get_tree().get_nodes_in_group("vehicles"):
		var vehicle := node as Node3D
		if vehicle == null or not data.get(String(vehicle.name)) is Dictionary:
			continue
		var saved: Dictionary = data[String(vehicle.name)]
		vehicle.global_transform = SaveData.dict_to_transform(
			saved.get("transform"), vehicle.global_transform
		)
		if vehicle is RigidBody3D:
			(vehicle as RigidBody3D).linear_velocity = Vector3.ZERO
			(vehicle as RigidBody3D).angular_velocity = Vector3.ZERO
		if "health" in vehicle and "max_health" in vehicle:
			vehicle.health = clampf(
				SaveData.number_or(saved.get("health"), vehicle.max_health), 0.0, vehicle.max_health
			)


func _player() -> Node3D:
	return _first("player") as Node3D


func _first(group: String) -> Node:
	var nodes := get_tree().get_nodes_in_group(group)
	return nodes[0] if not nodes.is_empty() else null
