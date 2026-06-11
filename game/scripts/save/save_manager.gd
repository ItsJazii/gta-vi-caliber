class_name SaveManager
extends Node
## Saves and restores world state: player position plus every vehicle's
## transform, motion, and health. Drop one into any world scene.
##
## Self-contained (streaming-ready): entities are found through the "player"
## and "vehicles" groups, never by cross-scene node paths. Vehicles are matched
## by node name, which is unique within a scene. (De)serialization math lives
## in SaveState (pure, unit-tested).

@export var save_path: String = "user://save.json"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("save_game"):
		save_game()
	elif event.is_action_pressed("load_game"):
		load_game()


func save_game() -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("save: cannot write %s" % save_path)
		return
	var data := SaveState.build(_capture_player(), _capture_vehicles())
	file.store_string(JSON.stringify(data, "\t"))
	print("game saved -> %s" % save_path)


func load_game() -> void:
	if not FileAccess.file_exists(save_path):
		push_warning("load: no save file at %s" % save_path)
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not SaveState.is_compatible(data):
		push_error("load: incompatible or corrupt save at %s" % save_path)
		return
	_apply_vehicles(data["vehicles"])
	_apply_player(data["player"])
	print("game loaded <- %s" % save_path)


func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player


func _capture_player() -> Dictionary:
	var player := _player()
	if player == null:
		return {}
	return {"position": SaveState.vec3_to_array(player.global_position)}


func _apply_player(data: Dictionary) -> void:
	var player := _player()
	if player == null:
		return
	player.eject()
	player.velocity = Vector3.ZERO
	player.global_position = SaveState.array_to_vec3(data.get("position"), player.global_position)


func _capture_vehicles() -> Dictionary:
	var vehicles := {}
	for node in get_tree().get_nodes_in_group("vehicles"):
		var car := node as Car
		if car == null:
			continue
		vehicles[String(car.name)] = {
			"transform": SaveState.transform_to_dict(car.global_transform),
			"health": car.health,
		}
	return vehicles


func _apply_vehicles(data: Dictionary) -> void:
	for node in get_tree().get_nodes_in_group("vehicles"):
		var car := node as Car
		if car == null or not data.get(String(car.name)) is Dictionary:
			continue
		var saved: Dictionary = data[String(car.name)]
		car.global_transform = SaveState.dict_to_transform(
			saved.get("transform"), car.global_transform
		)
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		car.health = clampf(
			SaveState.number_or(saved.get("health"), car.max_health), 0.0, car.max_health
		)
