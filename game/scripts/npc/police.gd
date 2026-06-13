class_name Police
extends CharacterBody3D
## Police responder: patrols near a post, then engages the nearest player while a
## WantedTracker reports an active wanted level. While `fires_weapon` (the
## default) the officer runs the pure PoliceCombat brain — advancing, holding the
## firing band, taking cover, and shooting back with heat-scaled firepower; with
## it off the officer reverts to the old melee-only chase.
##
## Reuses CharacterAnimator for procedural running and Damageable for health
## (shootable like any NPC — and shooting a cop is itself a crime). All decisions
## are pure/tested (PoliceCombat → CombatAi + PoliceResponse, NpcBrain steering);
## this node just owns state, raycasts, and moves the body.

@export var patrol_speed: float = 2.6
@export var chase_speed: float = 7.0
@export var wander_radius: float = 6.0
@export var arrive_tolerance: float = 1.0
@export var idle_time: float = 1.2
## Stops chasing (an "arrest" hold) once this close to the target.
@export var catch_distance: float = 1.8
## Damage per second dealt to the player while within catch_distance (melee mode).
@export var attack_dps: float = 22.0
@export var acceleration: float = 16.0
@export var max_health: float = 70.0
@export var respawn_delay: float = 6.0

@export_group("Gunfire")
## When true, the officer shoots back via PoliceCombat; when false, melee only.
@export var fires_weapon: bool = true
## Damage per landed hitscan shot.
@export var fire_damage: float = 12.0
## Eye height for the line-of-sight / firing raycast (matches the player camera).
@export var eye_height: float = 1.5
## How fast (rad/s) the officer swings its aim toward the player.
@export var aim_turn_rate: float = 7.0
## Rounds per magazine before a reload pause.
@export var clip_size: int = 12
## Seconds spent reloading (the officer repositions/retreats meanwhile).
@export var reload_time: float = 2.2

@export_group("Pursuit")
## How far the officer can spot the player, with a clear line of sight.
@export var sight_range: float = 45.0
## Seconds out of sight before the officer abandons the chase and resumes patrol —
## the window the player must stay hidden to "go cold".
@export var give_up_time: float = 8.0

var _target: Vector3 = Vector3.ZERO
var _home: Vector3 = Vector3.ZERO
var _idle_left: float = 0.0
var _dead: bool = false
var _hp: Damageable
var _rng := RandomNumberGenerator.new()
var _fire_cd: float = 0.0
var _reload_left: float = 0.0
var _ammo: int = 12
var _strafe_sign: float = 1.0
var _facing: Vector3 = Vector3.FORWARD
var _last_known: Vector3 = Vector3.ZERO
var _time_unseen: float = 0.0
var _engaged: bool = false
var _gave_up: bool = false
var _flinch_until: float = 0.0

@onready var _rig: CharacterAnimator = $Rig


func _ready() -> void:
	_rng.randomize()
	_home = global_position
	_hp = Damageable.new(max_health)
	_ammo = clip_size
	_strafe_sign = 1.0 if _rng.randf() < 0.5 else -1.0
	_last_known = global_position
	add_to_group("police")
	_pick_patrol()


func _physics_process(delta: float) -> void:
	if _dead:
		_fall(delta)
		return

	_fire_cd = maxf(0.0, _fire_cd - delta)
	var player := _nearest_player()
	var move: Dictionary
	if player != null and _is_wanted():
		move = _pursue(player, delta)
	else:
		# Heat's off — forget the chase so the next spree gets a fresh response.
		_engaged = false
		_gave_up = false
		move = _wander_step(delta)
	var dir: Vector3 = move["dir"]
	var speed: float = move["speed"]

	if not is_on_floor():
		velocity += get_gravity() * delta
	var target_v := dir * speed
	velocity.x = move_toward(velocity.x, target_v.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_v.z, acceleration * delta)
	move_and_slide()
	_rig.animate(Vector3(velocity.x, 0.0, velocity.z), is_on_floor(), velocity.y, false, delta)


## Duck-typed weapon target entry point.
func take_damage(amount: float, _point: Vector3, _normal: Vector3) -> void:
	if _dead:
		return
	if _hp.apply(amount):
		_die()


func is_dead() -> bool:
	return _dead


## A quick recoil jolt of the rig when hit — same impact tell as a civilian,
## self-limiting against rapid fire and inert once down. `_dir` is reserved for a
## future directional stagger.
func flinch(_dir: Vector3) -> void:
	if _dead or _rig == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _flinch_until:
		return
	_flinch_until = now + 0.22
	var tween := create_tween()
	tween.tween_property(_rig, "rotation:x", deg_to_rad(-13.0), 0.05)
	tween.tween_property(_rig, "rotation:x", 0.0, 0.17)


## Chase in three phases while wanted:
##   APPROACH — not yet seen: home in on the player's position from dispatch intel
##     (so cops spawned beyond sight range still converge).
##   ENGAGED  — has sight or recently had it: fight; when sight breaks, steer to
##     the last spot they were seen (not the live position, so they can't track
##     through walls) and search there.
##   GAVE_UP  — out of sight past give_up_time: this officer peels off to patrol
##     and won't re-approach until it actually re-sights the player. Other and
##     newly dispatched officers keep coming, so the player shakes the heat by
##     surviving the wanted level (which decays), not by juking one cop.
func _pursue(player: Node3D, delta: float) -> Dictionary:
	var shot := _ray_to(player)
	var seen := _sees(player, shot)
	if seen:
		_engaged = true
		_gave_up = false
		_time_unseen = 0.0
		_last_known = player.global_position
	elif _engaged:
		_time_unseen += delta
		if PursuitMemory.should_give_up(_time_unseen, give_up_time):
			_engaged = false
			_gave_up = true
			_pick_patrol()

	if _gave_up:
		return _wander_step(delta)
	# ENGAGED steers to the last-known point when blind; APPROACH uses live intel.
	var aim := (
		PursuitMemory.target(seen, player.global_position, _last_known)
		if _engaged
		else player.global_position
	)
	if fires_weapon:
		return _combat_step(player, delta, aim, seen, shot)
	return _melee_step(player, delta)


## A clear line of sight to the player within spotting range.
func _sees(player: Node3D, shot: Dictionary) -> bool:
	if NpcBrain.planar_distance(global_position, player.global_position) > sight_range:
		return false
	return _los_clear(shot)


## Idle patrol wander around the post.
func _wander_step(delta: float) -> Dictionary:
	if NpcBrain.arrived(global_position, _target, arrive_tolerance):
		_idle_left -= delta
		if _idle_left <= 0.0:
			_pick_patrol()
		return {"dir": Vector3.ZERO, "speed": 0.0}
	return {"dir": NpcBrain.planar_dir(global_position, _target), "speed": patrol_speed}


## Run the pure PoliceCombat brain and execute the plan — turn toward the aim
## point, fire if told to, and return the movement intent. `aim` is the live
## player while seen, else the last-known spot; `seen` gates engaging/firing so a
## blind officer advances on the memory instead of shooting through cover.
func _combat_step(
	player: Node3D, delta: float, aim: Vector3, seen: bool, shot: Dictionary
) -> Dictionary:
	var to_target := CombatAi.planar_dir(global_position, aim)
	var distance := NpcBrain.planar_distance(global_position, aim)
	_turn_toward(to_target, delta)
	if _ammo <= 0:
		_reload_left = maxf(0.0, _reload_left - delta)
		if _reload_left <= 0.0:
			_ammo = clip_size

	var stars := _current_stars()
	var plan := PoliceCombat.plan(
		distance, seen, _facing, to_target, _hp.health_fraction(), stars, _ammo, _fire_cd <= 0.0
	)
	var action: int = plan["action"]
	if bool(plan["fire"]):
		_fire_at(player, shot)
		_ammo -= 1
		_fire_cd = PoliceCombat.fire_cooldown(stars)
		if _ammo <= 0:
			_reload_left = reload_time

	return {
		"dir": CombatAi.desired_move(action, global_position, aim, _strafe_sign),
		"speed": CombatAi.move_speed(action, PoliceCombat.chase_speed(chase_speed, stars)),
	}


## Legacy melee chase used when `fires_weapon` is off: close in, then punch.
func _melee_step(player: Node3D, delta: float) -> Dictionary:
	if NpcBrain.planar_distance(global_position, player.global_position) > catch_distance:
		return {
			"dir": NpcBrain.pursue_dir(global_position, player.global_position),
			"speed": chase_speed
		}
	_attack(delta)
	return {"dir": Vector3.ZERO, "speed": 0.0}


## Swing the planar aim heading toward `to_target` at aim_turn_rate, so the
## officer must finish turning before CombatAi's firing arc lets it shoot.
func _turn_toward(to_target: Vector3, delta: float) -> void:
	if to_target.length() < 0.001:
		return
	var cur := Vector2(_facing.x, _facing.z)
	if cur.length() < 0.001:
		_facing = to_target
		return
	var step := clampf(
		cur.angle_to(Vector2(to_target.x, to_target.z)),
		-aim_turn_rate * delta,
		aim_turn_rate * delta
	)
	var rotated := cur.rotated(step)
	_facing = Vector3(rotated.x, 0.0, rotated.y).normalized()


func _current_stars() -> int:
	for tracker in get_tree().get_nodes_in_group("wanted"):
		if tracker.has_method("stars"):
			return tracker.stars()
	return 0


## True if a precomputed eyes-to-eyes raycast reaches the player unobstructed —
## i.e. a clear shot. A wall (or any non-player body) in between blocks it.
func _los_clear(shot: Dictionary) -> bool:
	if shot.is_empty():
		return true
	var collider := shot.get("collider") as Node
	return collider != null and collider.is_in_group("player")


func _ray_to(player: Node3D) -> Dictionary:
	var from := global_position + Vector3.UP * eye_height
	var to := player.global_position + Vector3.UP * eye_height
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


## Resolve a hitscan shot (the same ray used for line-of-sight): deal damage only
## if the round actually reaches the player (no shooting through cover).
func _fire_at(player: Node3D, shot: Dictionary) -> void:
	if not shot.is_empty():
		var collider := shot.get("collider") as Node
		if collider == null or not collider.is_in_group("player"):
			return
	var point: Vector3 = (
		shot["position"]
		if not shot.is_empty()
		else player.global_position + Vector3.UP * eye_height
	)
	for health in get_tree().get_nodes_in_group("player_health"):
		if health.has_method("take_damage"):
			health.take_damage(fire_damage, point, Vector3.UP)


func _attack(delta: float) -> void:
	for health in get_tree().get_nodes_in_group("player_health"):
		if health.has_method("take_damage"):
			health.take_damage(attack_dps * delta)


func _is_wanted() -> bool:
	for tracker in get_tree().get_nodes_in_group("wanted"):
		if tracker.has_method("is_wanted") and tracker.is_wanted():
			return true
	return false


func _pick_patrol() -> void:
	_idle_left = idle_time
	_target = NpcBrain.wander_target(_home, wander_radius, _rng.randf(), _rng.randf())


func _nearest_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] as Node3D if not players.is_empty() else null


func _fall(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()


func _die() -> void:
	_dead = true
	var tween := create_tween()
	tween.tween_property(_rig, "rotation:z", deg_to_rad(88.0), 0.4)
	if respawn_delay > 0.0:
		tween.tween_interval(respawn_delay)
		tween.tween_callback(_respawn)


func _respawn() -> void:
	_hp.revive()
	_dead = false
	_ammo = clip_size
	_fire_cd = 0.0
	_reload_left = 0.0
	_facing = Vector3.FORWARD
	_engaged = false
	_gave_up = false
	_time_unseen = 0.0
	_last_known = _home
	_rig.rotation = Vector3.ZERO
	global_position = _home
	velocity = Vector3.ZERO
	_pick_patrol()
