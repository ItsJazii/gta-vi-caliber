class_name LootCrate
extends StaticBody3D
## Shootable/meleeable crate that pays into the live LootDropDirector.
##
## WeaponController and MeleeController both call take_damage(amount, point,
## normal) on whatever they hit. This prop uses the same duck-typed combat
## contract as pedestrians and target dummies, then asks the live loot director
## to spawn an actual pickup at the crate.

signal smashed(drop_position: Vector3)
signal respawned

@export var max_health: float = 35.0
@export var respawn_delay: float = 18.0
@export var drop_offset: Vector3 = Vector3(0.0, 0.35, 0.0)
@export var drop_director_group: StringName = &"loot_drop"

var _hp: Damageable
var _smashed: bool = false
var _rest_transform: Transform3D
var _collision_shapes: Array[CollisionShape3D] = []


func _ready() -> void:
	add_to_group("loot_crates")
	_hp = Damageable.new(max_health)
	_rest_transform = transform
	_collect_collision_shapes(self)


func take_damage(amount: float, _point: Vector3, _normal: Vector3) -> void:
	if _smashed:
		return
	if _hp.apply(amount):
		_smash()


func is_dead() -> bool:
	return _smashed


func _smash() -> void:
	_smashed = true
	_set_enabled(false)
	var drop_position := global_position + drop_offset
	_drop_loot(drop_position)
	smashed.emit(drop_position)
	if respawn_delay > 0.0:
		get_tree().create_timer(respawn_delay).timeout.connect(_respawn)


func _drop_loot(drop_position: Vector3) -> void:
	var director := get_tree().get_first_node_in_group(String(drop_director_group))
	if director != null and director.has_method("drop_from_crate"):
		director.call("drop_from_crate", drop_position)


func _respawn() -> void:
	_hp.revive()
	_smashed = false
	transform = _rest_transform
	_set_enabled(true)
	respawned.emit()


func _set_enabled(value: bool) -> void:
	visible = value
	for shape in _collision_shapes:
		if is_instance_valid(shape):
			shape.disabled = not value


func _collect_collision_shapes(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionShape3D:
			_collision_shapes.append(child as CollisionShape3D)
		_collect_collision_shapes(child)
