class_name Pedestrian
extends CharacterBody3D
## A wandering, shootable street pedestrian.
##
## Reuses AnimatedRig for imported-character locomotion and Damageable for
## health; NpcBrain (pure, tested) drives the wander/idle/flee behaviour.
## Duck-typed take_damage makes it a valid weapon target, so the same gun that
## hits a dummy drops a pedestrian — and scares the rest into fleeing.

@export var walk_speed: float = 2.4
@export var run_speed: float = 6.0
@export var wander_radius: float = 12.0
@export var arrive_tolerance: float = 1.0
@export var idle_time: float = 1.6
@export var acceleration: float = 14.0
@export var max_health: float = 40.0
## A threat closer than this (m) forces a flee; fleeing stops past calm_radius.
@export var flee_radius: float = 8.0
@export var calm_radius: float = 16.0
## Seconds a pedestrian stays scared after being shot at.
@export var fear_duration: float = 6.0
@export var respawn_delay: float = 5.0

var _state: NpcBrain.State = NpcBrain.State.IDLE
var _target: Vector3 = Vector3.ZERO
var _home: Vector3 = Vector3.ZERO
var _threat_pos: Vector3 = Vector3.ZERO
var _idle_left: float = 0.0
var _fear: float = 0.0
var _greet_left: float = 0.0
var _dead: bool = false
var _hp: Damageable
var _rng := RandomNumberGenerator.new()
var _flinch_until: float = 0.0

@onready var _rig: AnimatedRig = $Rig


func _ready() -> void:
	_rng.randomize()
	_home = global_position
	_hp = Damageable.new(max_health)
	add_to_group("pedestrians")
	_pick_new_target()


func _physics_process(delta: float) -> void:
	if _dead:
		_fall(delta)
		return

	_fear = maxf(_fear - delta, 0.0)
	var player := _nearest_player()
	var threat_active := _fear > 0.0 and player != null
	if threat_active:
		_threat_pos = player.global_position

	if _greet_left > 0.0 and not threat_active:
		_answer_call(delta)
		return
	_rig.set_phone(false)
	var threat_distance := (
		NpcBrain.planar_distance(global_position, _threat_pos) if threat_active else 1000.0
	)
	_state = NpcBrain.next_state(_state, threat_active, threat_distance, flee_radius, calm_radius)

	var desired_dir := Vector3.ZERO
	var speed := NpcBrain.speed_for(_state, walk_speed, run_speed)
	match _state:
		NpcBrain.State.FLEE:
			desired_dir = NpcBrain.flee_dir(global_position, _threat_pos)
		NpcBrain.State.WANDER:
			if NpcBrain.arrived(global_position, _target, arrive_tolerance):
				_state = NpcBrain.State.IDLE
				_idle_left = idle_time
				speed = 0.0
			else:
				desired_dir = NpcBrain.planar_dir(global_position, _target)
		NpcBrain.State.IDLE:
			_idle_left -= delta
			if _idle_left <= 0.0:
				_pick_new_target()

	if not is_on_floor():
		velocity += get_gravity() * delta
	var target_v := desired_dir * speed
	velocity.x = move_toward(velocity.x, target_v.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_v.z, acceleration * delta)
	move_and_slide()
	_rig.animate(Vector3(velocity.x, 0.0, velocity.z), is_on_floor(), velocity.y, false, delta)


## Answer a phone call from the player: stop and hold a phone to the ear for
## `seconds`. Called (duck-typed) by the player when this is the nearest
## pedestrian as a friend's call connects. Ignored while dead; interrupted by fear.
func greet(seconds: float) -> void:
	if not _dead:
		_greet_left = maxf(_greet_left, seconds)


# Stand still with the phone-holding pose while a call is being "answered".
func _answer_call(delta: float) -> void:
	_greet_left -= delta
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()
	_rig.set_phone(true)
	_rig.animate(Vector3(velocity.x, 0.0, velocity.z), is_on_floor(), velocity.y, false, delta)


## Duck-typed weapon target entry point.
func take_damage(amount: float, point: Vector3, _normal: Vector3) -> void:
	if _dead:
		return
	_threat_pos = point
	_fear = fear_duration
	_state = NpcBrain.State.FLEE
	if _hp.apply(amount):
		_die()


func is_dead() -> bool:
	return _dead


## A quick recoil jolt of the rig when hit — the visible "ow" that sells a bullet
## or punch landing. Pitches the body back briefly, then settles. Self-limiting so
## a burst of fire can't stack tweens into a seizure, and inert once dead (the
## death topple owns the rig then). `_dir` is reserved for a directional flinch.
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
	_fear = 0.0
	_rig.rotation = Vector3.ZERO
	global_position = _home
	velocity = Vector3.ZERO
	_pick_new_target()


func _pick_new_target() -> void:
	_state = NpcBrain.State.WANDER
	_target = NpcBrain.wander_target(_home, wander_radius, _rng.randf(), _rng.randf())


func _nearest_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node3D
