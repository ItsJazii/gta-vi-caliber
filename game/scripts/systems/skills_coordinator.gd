class_name SkillsCoordinator
extends Node
## Live bridge for PlayerSkills.
##
## Owns the pure PlayerSkills model, trains it from activity already visible in
## the scene, and joins group "player_skills" so SaveManager can persist it.

@export var stamina_effort_per_meter: float = 0.04
@export var driving_effort_per_meter: float = 0.02
@export var shooting_hit_effort: float = 2.5

var skills: PlayerSkills = null

var _player: Node3D = null
var _weapon_controller: Node = null
var _weapon_connected: bool = false
var _last_player_pos: Vector3 = Vector3.ZERO
var _has_player_pos: bool = false
var _last_vehicle_pos: Vector3 = Vector3.ZERO
var _has_vehicle_pos: bool = false


func _ready() -> void:
	if skills == null:
		skills = PlayerSkills.new()
	add_to_group("player_skills")
	_player = _resolve_player()
	if _player != null:
		_set_player_baseline(_player.global_position)
	call_deferred("_bind_weapon_controller")


func _process(_delta: float) -> void:
	if _weapon_controller == null or not is_instance_valid(_weapon_controller):
		_weapon_controller = null
		_weapon_connected = false
	if not _weapon_connected:
		_bind_weapon_controller()
	_train_from_motion()


func train_activity(id: String, effort: float) -> float:
	return skills.train(id, effort) if skills != null else 0.0


func level(id: String) -> float:
	return skills.level(id) if skills != null else 0.0


func tier(id: String) -> String:
	return skills.tier(id) if skills != null else ""


func bonus(id: String) -> float:
	return skills.bonus(id) if skills != null else 0.0


func overall_mastery() -> float:
	return skills.overall_mastery() if skills != null else 0.0


func serialize() -> Dictionary:
	return {"skills": skills.to_dict() if skills != null else {}}


func restore(data: Dictionary) -> void:
	if skills == null:
		skills = PlayerSkills.new()
	var saved: Variant = data.get("skills", data)
	if saved is Dictionary:
		skills.load_dict(saved)
	_reset_motion_baselines()


func _bind_weapon_controller() -> void:
	var controller := get_tree().get_first_node_in_group("weapon_controller")
	if controller == null or not controller.has_signal("hit_confirmed"):
		return
	_weapon_controller = controller
	var callback := Callable(self, "_on_hit_confirmed")
	if not _weapon_controller.is_connected("hit_confirmed", callback):
		_weapon_controller.connect("hit_confirmed", callback)
	_weapon_connected = true


func _on_hit_confirmed(_killed: bool) -> void:
	train_activity("shooting", shooting_hit_effort)


func _train_from_motion() -> void:
	_player = _resolve_player()
	if _player == null:
		_reset_motion_baselines()
		return
	var driven := _driven_vehicle()
	if driven != null:
		_train_driving(driven)
		_set_player_baseline(_player.global_position)
		return
	_reset_vehicle_baseline()
	_train_stamina(_player)


func _train_stamina(player: Node3D) -> void:
	if not _has_player_pos:
		_set_player_baseline(player.global_position)
		return
	var meters := _planar_distance(_last_player_pos, player.global_position)
	_set_player_baseline(player.global_position)
	if player.visible and meters > 0.01:
		train_activity("stamina", meters * stamina_effort_per_meter)


func _train_driving(vehicle: Node3D) -> void:
	if not _has_vehicle_pos:
		_set_vehicle_baseline(vehicle.global_position)
		return
	var meters := _planar_distance(_last_vehicle_pos, vehicle.global_position)
	_set_vehicle_baseline(vehicle.global_position)
	if meters > 0.01:
		train_activity("driving", meters * driving_effort_per_meter)


func _driven_vehicle() -> Node3D:
	for node in get_tree().get_nodes_in_group("vehicles"):
		var vehicle := node as Node3D
		if vehicle == null or not vehicle.has_method("has_driver"):
			continue
		if bool(vehicle.call("has_driver")):
			return vehicle
	return null


func _resolve_player() -> Node3D:
	if _player != null and is_instance_valid(_player):
		return _player
	var parent := get_parent() as Node3D
	if parent != null and parent.is_in_group("player"):
		return parent
	return get_tree().get_first_node_in_group("player") as Node3D


func _set_player_baseline(pos: Vector3) -> void:
	_last_player_pos = pos
	_has_player_pos = true


func _set_vehicle_baseline(pos: Vector3) -> void:
	_last_vehicle_pos = pos
	_has_vehicle_pos = true


func _reset_motion_baselines() -> void:
	_has_player_pos = false
	_has_vehicle_pos = false


func _reset_vehicle_baseline() -> void:
	_has_vehicle_pos = false


func _planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
