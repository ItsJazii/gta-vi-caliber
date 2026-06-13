class_name PlayerHealth
extends Node
## World-level player health + regeneration + death/respawn.
##
## Finds the player via the "player" group, so it needs no edit to the player
## scene; joins "player_health" so damage sources (police, falls, future enemy
## fire) hit it by duck-typed take_damage. On death it respawns the player at a
## spawn point and clears the wanted level. The pure curve lives in
## PlayerHealthModel (tested).

signal changed(fraction: float)
signal died
signal respawned

@export var max_health: float = 100.0
@export var regen_rate: float = 12.0
@export var regen_delay: float = 5.0
@export var respawn_delay: float = 2.5

var _model: PlayerHealthModel
var _dead: bool = false


func _ready() -> void:
	_model = PlayerHealthModel.new(max_health, regen_rate, regen_delay)
	add_to_group("player_health")
	changed.emit(1.0)


func _process(delta: float) -> void:
	if _dead:
		return
	var before := _model.health
	_model.tick(delta)
	if not is_equal_approx(_model.health, before):
		changed.emit(_model.fraction())


## Duck-typed damage entry point for any attacker.
func take_damage(
	amount: float, _point: Vector3 = Vector3.ZERO, _normal: Vector3 = Vector3.ZERO
) -> void:
	if _dead:
		return
	# Body armor absorbs first. Shop-bought (and HUD-shown) armor lives on the
	# PlayerStats node, whose soak_damage had ZERO callers — so a paid vest gave
	# no protection and its HUD bar never drained. Route the hit through it and
	# send only the overflow to health. soak_damage also emits armor_changed, so
	# the HUD bar now drains correctly.
	var to_health := amount
	if amount > 0.0:
		var stats := get_tree().get_first_node_in_group("player_stats")
		if stats != null and stats.has_method("soak_damage"):
			to_health = float(stats.soak_damage(amount))
	if _model.apply(to_health):
		_die()
	else:
		changed.emit(_model.fraction())


func fraction() -> float:
	return _model.fraction()


func is_dead() -> bool:
	return _dead


## Heal from a pickup/medkit; ignored while dead (respawn handles that).
func heal(amount: float) -> void:
	if _dead:
		return
	_model.heal(amount)
	changed.emit(_model.fraction())


## Add body armor from a pickup; ignored while dead.
func add_armor(amount: float) -> void:
	if _dead:
		return
	_model.add_armor(amount)
	changed.emit(_model.fraction())


func armor_fraction() -> float:
	return _model.armor_fraction()


## Snapshot for SaveManager.
func serialize() -> Dictionary:
	return {"health": _model.health, "armor": _model.armor}


func restore(data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("health"):
		return
	var dict := data as Dictionary
	_model.health = clampf(float(dict["health"]), 0.0, _model.max_health)
	_model.armor = clampf(float(dict.get("armor", 0.0)), 0.0, _model.max_armor)
	_dead = _model.is_dead()
	changed.emit(_model.fraction())


func _die() -> void:
	_dead = true
	died.emit()
	changed.emit(0.0)
	get_tree().create_timer(respawn_delay).timeout.connect(_respawn)


func _respawn() -> void:
	_model.revive()
	_dead = false
	var player := _player()
	var spawn := _spawn_point()
	if player != null and spawn != null:
		player.global_position = spawn.global_position
		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity = Vector3.ZERO
	for tracker in get_tree().get_nodes_in_group("wanted"):
		if tracker.has_method("clear"):
			tracker.clear()
	respawned.emit()
	changed.emit(1.0)


func _player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] as Node3D if not players.is_empty() else null


func _spawn_point() -> Node3D:
	var spawns := get_tree().get_nodes_in_group("spawn_points")
	return spawns[0] as Node3D if not spawns.is_empty() else null
