class_name Grenade
extends RigidBody3D
## A thrown fragmentation grenade: arcs under physics, counts down a fuse, then
## detonates — radial damage (ExplosionMath, tested) to everyone in range, a
## camera shake, a light flash, and a wanted bump if it hurts people.
##
## Damage is dealt by iterating the people/prop groups rather than a physics
## shape query, so it needs no collision bookkeeping and hits anything with a
## duck-typed take_damage (pedestrians, police, hittables, the player).

@export var fuse: float = 1.8
@export var inner_radius: float = 2.5
@export var outer_radius: float = 7.5
@export var max_damage: float = 120.0
@export var camera_shake: float = 0.8

var _elapsed: float = 0.0
var _detonated: bool = false


func _ready() -> void:
	add_to_group("grenades")


func _physics_process(delta: float) -> void:
	if _detonated:
		return
	_elapsed += delta
	if _elapsed >= fuse:
		_detonate()


func _detonate() -> void:
	_detonated = true
	var here := global_position
	var hit_person := false
	for group in ["pedestrians", "police", "hittables"]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body == null or not body.has_method("take_damage"):
				continue
			var damage := ExplosionMath.radial_damage(
				here.distance_to(body.global_position), inner_radius, outer_radius, max_damage
			)
			if damage <= 0.0:
				continue
			body.take_damage(damage, body.global_position, Vector3.UP)
			if group != "hittables":
				hit_person = true
	_damage_player(here)
	if hit_person:
		_report_crime()
	_shake()
	_flash(here)
	queue_free()


func _damage_player(here: Vector3) -> void:
	var player := _player()
	if player == null:
		return
	var damage := ExplosionMath.radial_damage(
		here.distance_to(player.global_position), inner_radius, outer_radius, max_damage
	)
	if damage <= 0.0:
		return
	for health in get_tree().get_nodes_in_group("player_health"):
		if health.has_method("take_damage"):
			health.take_damage(damage)


func _report_crime() -> void:
	# Explosions are heard, not just seen — they bypass the CrimeWitness gate
	# that quiet gun/melee crimes go through and always land heat.
	for tracker in get_tree().get_nodes_in_group("wanted"):
		if tracker.has_method("report_crime"):
			tracker.report_crime(true)


func _shake() -> void:
	var node: Node = get_viewport().get_camera_3d()
	while node != null:
		if node.has_method("add_shake"):
			node.add_shake(camera_shake)
			return
		node = node.get_parent()


func _flash(here: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.35)
	light.light_energy = 8.0
	light.omni_range = outer_radius
	scene.add_child(light)
	light.global_position = here + Vector3.UP * 0.5
	get_tree().create_timer(0.12).timeout.connect(light.queue_free)


func _player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] as Node3D if not players.is_empty() else null
