class_name MeleeController
extends Node
## Unarmed melee: an escalating punch/kick brawl on the melee key.
##
## Two pure cores compose here (neither owns the other): MeleeAttack paces each
## swing's windup/strike/recover and lets a press during recovery chain the next
## hit, while MeleeCombat owns the brawl economy — the running combo, the strike
## it escalates to (jab → cross → kick → heavy), the stamina each costs, and the
## combo-scaled damage. This node is the scene glue: it reads the "melee" action,
## gates a swing on having the stamina for the next strike, runs the hit query
## from the player's chest along the camera heading during the active window, and
## damages whatever person or prop is in reach (duck-typed take_damage). Hitting a
## person is a crime, so it raises the wanted level just like gunfire. Stamina
## regenerates between flurries, so mashing heavies gasses you out. Self-contained:
## finds the player/camera by group/viewport, and only triggers while unarmed so
## it never fights the gun.

@export var reach: float = 2.2
@export var chest_height: float = 1.1
## Brawler stamina pool; heavier strikes drain more (see MeleeCombat.STAMINA_COST).
@export var max_stamina: float = 100.0

var _attack: MeleeAttack
var _combat: MeleeCombat
var _player: Node3D = null
var _was_active: bool = false


func _ready() -> void:
	_attack = MeleeAttack.new()
	_combat = MeleeCombat.new(max_stamina)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("melee"):
		return
	if _armed() or not _attack.can_start():
		return
	# Gate the swing on stamina for the strike this hit would escalate to, so a
	# spent fighter can't keep throwing haymakers.
	var next_strike := MeleeCombat.strike_for_combo(_combat.combo_count() + 1)
	if _combat.can_strike(next_strike):
		_attack.start()


func _physics_process(delta: float) -> void:
	_attack.tick(delta)
	if _attack.consume_hit():
		_strike()
	# The chain just lapsed back to rest: drop the combo and let stamina recover
	# while idle (never mid-swing, so a flurry spends without refunding itself).
	var active := _attack.is_active()
	if _was_active and not active:
		_combat.reset_combo()
	if not active:
		_combat.regen_stamina(delta)
	_was_active = active


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
	# Throw the strike: this escalates the combo and spends its stamina. A spent
	# fighter (returns 0) still whiffs the swing — no damage, no crime.
	var strike := MeleeCombat.strike_for_combo(_combat.combo_count() + 1)
	var damage := _combat.strike(strike)
	if damage <= 0.0:
		return
	var origin := player.global_position + Vector3(0.0, chest_height, 0.0)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * reach)
	if player is CollisionObject3D:
		query.exclude = [(player as CollisionObject3D).get_rid()]
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(query)
	var collider: Object = hit.get("collider") if not hit.is_empty() else null
	if collider == null or not collider.has_method("take_damage"):
		return
	collider.take_damage(damage, hit.position, hit.normal)
	if collider.has_method("flinch"):
		collider.flinch(forward)
	var node := collider as Node
	if node != null and (node.is_in_group("pedestrians") or node.is_in_group("police")):
		var killed: bool = collider.has_method("is_dead") and collider.is_dead()
		_report_crime(killed, hit.position)


func _report_crime(killed: bool, crime_pos: Vector3) -> void:
	for tracker in get_tree().get_nodes_in_group("wanted"):
		if tracker.has_method("report_witnessed_crime"):
			tracker.report_witnessed_crime(killed, crime_pos)


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
