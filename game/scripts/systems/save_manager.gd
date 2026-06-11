class_name SaveManager
extends Node
## Quick-save (F5) / quick-load (F9) of game state.
##
## Gathers a snapshot from the player and the systems that own state (health,
## wanted) by group, serialises it via SaveData (pure, tested), and writes it to
## user://savegame.json. Uses raw key input so it adds no input actions, and
## finds everything by group so it needs no edits to the player scene. Player
## position, health, and wanted level persist.

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
		var pos := player.global_position
		snapshot["player_pos"] = [pos.x, pos.y, pos.z]
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
	if player != null and snapshot.has("player_pos"):
		var values: Array = snapshot["player_pos"]
		if values.size() == 3:
			player.global_position = Vector3(values[0], values[1], values[2])
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


func _first(group: String) -> Node:
	var nodes := get_tree().get_nodes_in_group(group)
	return nodes[0] if not nodes.is_empty() else null
