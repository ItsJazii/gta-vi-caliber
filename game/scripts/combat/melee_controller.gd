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
## How head-on a body must be to take the punch: dot(forward, dir_to_target).
## 0.25 ≈ a forgiving ~75° front cone so a swing connects without pixel-aim.
@export var min_facing: float = 0.25

var _attack: MeleeAttack
var _combat: MeleeCombat
var _player: Node3D = null
var _was_active: bool = false
var _hitstop: Hitstop = null
var _impact_audio: MeleeImpactAudio = null


func _ready() -> void:
	_attack = MeleeAttack.new()
	_combat = MeleeCombat.new(max_stamina)
	# Code-spawned so the melee impact crunch + sound stay self-contained (mirrors
	# WeaponController). No scene wiring, no autoload.
	_hitstop = Hitstop.new()
	add_child(_hitstop)
	_impact_audio = MeleeImpactAudio.new()
	add_child(_impact_audio)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("melee"):
		return
	if _armed() or not _attack.can_start():
		return
	# Gate the swing on stamina for the strike this hit would escalate to, so a
	# spent fighter can't keep throwing haymakers.
	var next_strike := MeleeCombat.strike_for_combo(_combat.combo_count() + 1)
	if _combat.can_strike(next_strike) and _attack.start():
		_play_punch(_attack.combo)


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
	var collider := _find_target(player, forward)
	if collider == null:
		return
	var point: Vector3 = (collider as Node3D).global_position + Vector3(0.0, chest_height, 0.0)
	collider.take_damage(damage, point, -forward)
	if collider.has_method("flinch"):
		collider.flinch(forward)
	# A connecting strike earns an impact freeze, weighted by the strike (a
	# haymaker crunches harder than a jab) and meatiest on a kill — the same
	# Hitstop the gun uses. Hoisted out of the crime branch so a prop hit (no
	# is_dead) reads as a non-kill and still crunches.
	var killed: bool = collider.has_method("is_dead") and collider.is_dead()
	if _hitstop != null:
		var dose := MeleeCombat.hitstop_for_strike(strike, killed)
		_hitstop.hit(dose["seconds"], dose["scale"])
	# A connecting strike also plays a synthesized impact, weighted by strike and
	# meatiest on a kill. Same connect branch as the hitstop, so a whiff is silent.
	if _impact_audio != null:
		_impact_audio.play(strike, killed)
	var node := collider as Node
	if node != null and (node.is_in_group("pedestrians") or node.is_in_group("police")):
		_report_crime(killed, point)


## The body this swing connects with, or null. A forgiving sphere sweep in front
## of the chest (instead of a single hair-thin ray) gathers nearby damageable
## bodies, and MeleeCombat.best_target picks the most head-on one in reach — so a
## punch lands on the pedestrian you're facing without frame-perfect aim.
func _find_target(player: Node3D, forward: Vector3) -> Object:
	var space := get_viewport().world_3d.direct_space_state
	if space == null:
		return null
	var shape := SphereShape3D.new()
	shape.radius = reach * 0.75
	var center := player.global_position + Vector3(0.0, chest_height, 0.0) + forward * (reach * 0.5)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, center)
	params.collide_with_bodies = true
	if player is CollisionObject3D:
		params.exclude = [(player as CollisionObject3D).get_rid()]
	var bodies: Array = []
	var points := PackedVector3Array()
	for hit in space.intersect_shape(params, 16):
		var collider: Object = hit.get("collider")
		var col_node := collider as Node3D
		if col_node == null or not collider.has_method("take_damage"):
			continue
		bodies.append(collider)
		points.append(col_node.global_position)
	var index := MeleeCombat.best_target(points, player.global_position, forward, reach, min_facing)
	return bodies[index] if index != MeleeCombat.NO_TARGET else null


## Play the swing's punch animation on the player's rig (jab/cross alternating
## with the combo step). Triggered at swing start so the windup is visible.
func _play_punch(combo: int) -> void:
	var player := _get_player()
	if player == null:
		return
	var rig := player.get_node_or_null("Rig") as AnimatedRig
	if rig != null:
		rig.play_punch(combo)


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
