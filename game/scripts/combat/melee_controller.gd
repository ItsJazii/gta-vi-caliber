class_name MeleeController
extends Node
## Unarmed melee: a short forward strike on the melee key.
##
## Swing/combo timing is MeleeAttack (pure, tested); this node reads the attack
## key, runs the hit query from the player's chest along the camera's heading
## during the active window, and damages whatever person or prop is in reach
## (duck-typed take_damage). Hitting a person is a crime, so it raises the
## wanted level just like gunfire. Self-contained: finds the player/camera by
## group/viewport, uses a raw key so it adds no input actions, and only triggers
## while unarmed so it never fights the gun.

@export var melee_key: int = KEY_V
@export var base_damage: float = 16.0
@export var reach: float = 2.2
@export var chest_height: float = 1.1

var _attack: MeleeAttack
var _player: Node3D = null


func _ready() -> void:
	_attack = MeleeAttack.new()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != melee_key:
		return
	if not _armed():
		_attack.start()


func _physics_process(delta: float) -> void:
	_attack.tick(delta)
	if _attack.consume_hit():
		_strike()


func _strike() -> void:
	var player := _get_player()
	var cam := get_viewport().get_camera_3d()
	if player == null or cam == null:
		return
	var forward := -cam.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		return
	forward = forward.normalized()
	var origin := player.global_position + Vector3(0.0, chest_height, 0.0)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * reach)
	if player is CollisionObject3D:
		query.exclude = [(player as CollisionObject3D).get_rid()]
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(query)
	var collider: Object = hit.get("collider") if not hit.is_empty() else null
	if collider == null or not collider.has_method("take_damage"):
		return
	collider.take_damage(_attack.combo_damage(base_damage), hit.position, hit.normal)
	var node := collider as Node
	if node != null and (node.is_in_group("pedestrians") or node.is_in_group("police")):
		var killed: bool = collider.has_method("is_dead") and collider.is_dead()
		_report_crime(killed)


func _report_crime(killed: bool) -> void:
	for tracker in get_tree().get_nodes_in_group("wanted"):
		if tracker.has_method("report_crime"):
			tracker.report_crime(killed)


func _armed() -> bool:
	for controller in get_tree().get_nodes_in_group("weapon_controller"):
		if controller.has_method("is_armed") and controller.is_armed():
			return true
	return false


func _get_player() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		var players := get_tree().get_nodes_in_group("player")
		_player = players[0] as Node3D if not players.is_empty() else null
	return _player
