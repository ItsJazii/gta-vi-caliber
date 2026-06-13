class_name Player
extends CharacterBody3D
## Third-person player controller: walk, sprint, jump.
##
## Movement math is delegated to PlayerMotion (pure, unit-tested). The camera
## is owned by the CameraRig child (OrbitCamera); we only read its yaw so
## input is camera-relative.

## Fired on each footfall while moving on the ground. `surface` is a key from
## Footsteps (e.g. "grass") and `is_left` tells which foot landed. Cadence
## comes from the rig's animation foot plants (AnimatedRig.foot_planted), so
## audio stays locked to the visible steps; surface logic is in Footsteps.
signal footstep(surface: String, is_left: bool)

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var acceleration: float = 30.0
@export var deceleration: float = 45.0
@export_range(0.0, 1.0) var air_control: float = 0.35
@export var jump_velocity: float = 4.8
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.12
@export var climb_speed: float = 3.0
## Swimming. Horizontal paddle speed, vertical stroke speed (surface/dive keys),
## and how briskly velocity eases toward the target through the water's drag.
@export var swim_speed: float = 4.0
@export var swim_vertical_speed: float = 3.0
@export var swim_acceleration: float = 12.0
## Submersion fractions (of body height) for the swim hysteresis: start
## swimming once chest-deep, keep swimming until back down to wading depth.
@export_range(0.0, 1.0) var swim_enter_fraction: float = 0.6
@export_range(0.0, 1.0) var swim_exit_fraction: float = 0.45
## Where the body floats at rest, and how hard/fast buoyancy corrects toward it.
@export_range(0.0, 1.0) var swim_neutral_fraction: float = 0.62
@export var buoyancy_strength: float = 6.0
@export var buoyancy_max_speed: float = 1.5
## Body height (m) used for submersion; matches the collision capsule.
@export var body_height: float = 1.8
## How close (m) a vehicle must be for the interact key to enter it.
@export var enter_vehicle_range: float = 3.5
## How close (m) an interactable must be for the interact key to use it. Shorter
## than the vehicle reach so a parked car keeps priority on the shared key.
@export var interact_reach: float = 2.2
## Gamepad left-stick conditioning for analog walking, merged with the keyboard
## move vector via StickInput.movement (the harder-pushed source wins).
@export_range(0.0, 0.9) var move_stick_deadzone: float = 0.2
@export_range(1.0, 4.0) var move_stick_exponent: float = 1.6
## Steep-slope slide: floors whose up-normal y falls below slide_max_walk_normal_y
## (cos of the steepest stable angle, ~0.82 ≈ 35°) push the player down the fall
## line at up to slide_accel (m/s²), so steep ground can't be casually walked up.
@export var slide_max_walk_normal_y: float = 0.82
@export var slide_accel: float = 18.0
## Landing camera shake: downward speed (m/s) at touchdown below which nothing
## registers, the speed mapped to a full jolt, and that jolt's peak trauma.
@export var land_shake_min_speed: float = 4.5
@export var land_shake_max_speed: float = 16.0
@export_range(0.0, 1.0) var land_shake_max_trauma: float = 0.5
## Fall damage: landing downward speed (m/s) below which it's harmless, the speed
## at which it deals fall_max_damage, and that peak hit (~full health = lethal).
@export var fall_safe_speed: float = 9.0
@export var fall_lethal_speed: float = 22.0
@export var fall_max_damage: float = 100.0
## Breath: seconds of air with the head under, how far down (submersion) counts
## as submerged, surface recovery rate, and drowning damage per second at empty.
@export var breath_seconds: float = 12.0
@export_range(0.0, 1.0) var head_submersion_fraction: float = 0.9
@export var oxygen_recover_rate: float = 0.5
@export var drown_damage_per_second: float = 10.0

var _time_since_grounded: float = 0.0
var _time_since_jump_pressed: float = 1.0
var _jump_spent: bool = false
var _vehicle: Node3D = null
var _swimming: bool = false
var _phone_ui: Phone = null
var _interact_prompt: InteractPrompt = null
var _was_on_floor: bool = true
var _oxygen: float = 1.0
# Per-physics-frame group probes (water overlap, ladder overlap, damage sink)
# read these caches instead of re-scanning the SceneTree groups every frame.
var _water_cache: GroupCache = null
var _ladder_cache: GroupCache = null
var _health_cache: GroupCache = null

@onready var _camera_rig: OrbitCamera = $CameraRig
@onready var _rig: AnimatedRig = $Rig


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Footstep audio is created in code (not the scene) so it stays self-
	# contained and doesn't collide with parallel edits to player.tscn.
	var footstep_audio := FootstepAudio.new()
	add_child(footstep_audio)
	footstep.connect(footstep_audio.on_footstep)
	_rig.foot_planted.connect(_on_foot_planted)
	# The phone (UI + its own input + holding pose) is likewise code-spawned so
	# the feature is self-contained and doesn't touch player.tscn.
	_phone_ui = Phone.new()
	add_child(_phone_ui)
	_phone_ui.active_changed.connect(_on_phone_active)
	_phone_ui.friend_called.connect(_on_friend_called)
	_water_cache = GroupCache.for_group(get_tree(), "water")
	_ladder_cache = GroupCache.for_group(get_tree(), "ladders")
	_health_cache = GroupCache.for_group(get_tree(), "player_health")
	# The interact-prompt overlay is likewise code-spawned so the feature stays
	# self-contained and doesn't touch player.tscn.
	_interact_prompt = InteractPrompt.new()
	add_child(_interact_prompt)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_mouse_capture()
	elif event.is_action_pressed("interact") and not _on_phone():
		if not _toggle_vehicle():
			_try_interact()


## True while the phone is raised — gates sprint and vehicle entry so the player
## is committed to a one-handed walking pose while scrolling or on a call.
func _on_phone() -> bool:
	return _phone_ui != null and _phone_ui.is_active()


# Mirror the raised/pocketed phone onto the rig's one-handed holding pose.
func _on_phone_active(active: bool) -> void:
	_rig.set_phone(active)


# A call connected: if a pedestrian is nearby, they "answer" — stop and raise
# their own phone to an ear — so calling a friend you can see reads in-world.
func _on_friend_called(_friend_name: String) -> void:
	var ped := _nearest_pedestrian(30.0)
	if ped != null and ped.has_method("greet"):
		ped.greet(6.0)


func _nearest_pedestrian(max_range: float) -> Node3D:
	var best: Node3D = null
	var best_distance := max_range
	for node in get_tree().get_nodes_in_group("pedestrians"):
		var ped := node as Node3D
		if ped == null:
			continue
		var distance := global_position.distance_to(ped.global_position)
		if distance <= best_distance:
			best = ped
			best_distance = distance
	return best


func _physics_process(delta: float) -> void:
	_update_interact_prompt()
	if _vehicle != null:
		global_position = _vehicle.global_position
		# Keep feeding the rig (grounded, no motion) while driving: its
		# AnimationTree stays active even hidden, and a frozen mid-run blend
		# would keep firing foot plants from inside the car. Grounded-idle
		# also means stepping out resumes from a clean standing pose.
		_rig.animate(Vector3.ZERO, true, 0.0, false, delta)
		return

	_update_jump_timers(delta)
	if _update_swimming(delta):
		return

	var input_dir := _move_input()
	var direction := PlayerMotion.direction_from_input(input_dir, _camera_rig.gameplay_yaw())

	if _is_on_ladder(delta) and (input_dir.y < 0.0 or not is_on_floor()):
		velocity = PlayerMotion.climb_velocity(input_dir, direction, climb_speed)
		move_and_slide()
		_drive_rig(delta, true)
		return

	if not is_on_floor():
		velocity += get_gravity() * delta
	if PlayerMotion.should_jump(
		_time_since_grounded, coyote_time, _time_since_jump_pressed, jump_buffer_time, _jump_spent
	):
		velocity.y = jump_velocity
		_jump_spent = true
		_time_since_jump_pressed = jump_buffer_time + 1.0

	var sprinting := Input.is_action_pressed("sprint") and not _on_phone()
	var speed := sprint_speed if sprinting else walk_speed
	var target := PlayerMotion.horizontal_velocity(direction, speed)
	var rate := PlayerMotion.acceleration_rate(
		not input_dir.is_zero_approx(), is_on_floor(), acceleration, deceleration, air_control
	)
	velocity = PlayerMotion.accelerated(velocity, target, rate, delta)
	if is_on_floor():
		velocity += (
			PlayerMotion.slope_slide(get_floor_normal(), slide_max_walk_normal_y, slide_accel)
			* delta
		)
	var impact_speed := maxf(-velocity.y, 0.0)
	move_and_slide()
	_drive_rig(delta, false)
	_update_landing(impact_speed)


## This frame's merged move vector: keyboard WASD combined with the conditioned
## left stick (the harder-pushed source wins). Shared by walking and swimming.
func _move_input() -> Vector2:
	var keys := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var stick := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	)
	return StickInput.movement(keys, stick, move_stick_deadzone, move_stick_exponent)


## Swim when chest-deep in any "water" volume. Returns true once it has taken
## over movement for the frame (so _physics_process skips the walk path). Pure
## submersion / hysteresis / stroke math lives in SwimMotion; this just samples
## the water surface by overlap and applies the result. Surface = jump, dive =
## the dive action; with no vertical key the body bobs at the waterline.
func _update_swimming(delta: float) -> bool:
	var water := _current_water(delta)
	if water == null:
		_swimming = false
		_update_breath(0.0, delta)
		return false

	var fraction := SwimMotion.submersion(global_position.y, water.surface_y(), body_height)
	_update_breath(fraction, delta)
	_swimming = SwimMotion.is_swimming(fraction, _swimming, swim_enter_fraction, swim_exit_fraction)
	if not _swimming:
		return false

	var direction := PlayerMotion.direction_from_input(_move_input(), _camera_rig.gameplay_yaw())
	var axis := SwimMotion.vertical_axis(
		Input.is_action_pressed("jump"), Input.is_action_pressed("dive")
	)
	var target := SwimMotion.target_velocity(direction, swim_speed, axis, swim_vertical_speed)
	if is_zero_approx(axis):
		target.y = SwimMotion.buoyancy(
			fraction, swim_neutral_fraction, buoyancy_strength, buoyancy_max_speed
		)
	velocity = velocity.move_toward(target, swim_acceleration * delta)
	move_and_slide()
	_drive_rig(delta, false)
	return true


## The water volume the body is currently inside, if any — Area3D nodes in group
## "water" (WaterVolume), found by overlap like ladders. First match wins. The
## candidate list is cached (GroupCache) since volumes only change on streaming.
func _current_water(delta: float) -> WaterVolume:
	for node in _water_cache.nodes(delta):
		var water := node as WaterVolume
		if water != null and water.overlaps_body(self):
			return water
	return null


## Feed the rig this frame's motion. Called after move_and_slide so velocity
## reflects collisions; the planar component drives the anim blend and facing.
func _drive_rig(delta: float, is_climbing: bool) -> void:
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	_rig.animate(planar, is_on_floor(), velocity.y, is_climbing, delta)


## On the frame the player touches down after being airborne, jolt the camera by
## the landing speed — a soft step-off registers nothing, a long fall thumps.
func _update_landing(impact_speed: float) -> void:
	var grounded := is_on_floor()
	if grounded and not _was_on_floor:
		var trauma := CameraShake.trauma_from_impact(
			impact_speed, land_shake_min_speed, land_shake_max_speed, land_shake_max_trauma
		)
		if trauma > 0.0:
			_camera_rig.add_shake(trauma)
		var damage := PlayerMotion.fall_damage(
			impact_speed, fall_safe_speed, fall_lethal_speed, fall_max_damage
		)
		if damage > 0.0:
			_hurt(damage)
	_was_on_floor = grounded


## Route damage (falls, drowning) through PlayerHealth (group "player_health"),
## the same public API pickups and weapons use — keeps Player decoupled from it.
## Drowning calls this every frame, so the sink list is cached.
func _hurt(amount: float) -> void:
	for health in _health_cache.nodes(get_physics_process_delta_time()):
		if health.has_method("take_damage"):
			health.take_damage(amount)


## Drain/refill the breath reserve from how submerged the head is, and once it's
## empty underwater, drown the player a bit each frame. Pure model in SwimMotion.
func _update_breath(submersion: float, delta: float) -> void:
	var underwater := SwimMotion.head_underwater(submersion, head_submersion_fraction)
	_oxygen = SwimMotion.next_oxygen(
		_oxygen, underwater, breath_seconds, oxygen_recover_rate, delta
	)
	if underwater and _oxygen <= 0.0:
		_hurt(drown_damage_per_second * delta)


## A locomotion clip planted a foot: tag the surface under us and re-emit as
## the public `footstep` signal that audio listens on.
func _on_foot_planted(is_left: bool) -> void:
	if is_on_floor():
		footstep.emit(_floor_surface(), is_left)


## Surface key under the player, read from the floor collider's groups. Falls
## back to the default surface when there's no contact or the floor is untagged.
func _floor_surface() -> String:
	var collision := get_last_slide_collision()
	if collision == null:
		return Footsteps.DEFAULT_SURFACE
	var collider := collision.get_collider(0)
	if collider is Node:
		return Footsteps.surface_for_groups((collider as Node).get_groups())
	return Footsteps.DEFAULT_SURFACE


func _is_on_ladder(delta: float) -> bool:
	for ladder in _ladder_cache.nodes(delta):
		var area := ladder as Area3D
		if area != null and area.overlaps_body(self):
			return true
	return false


## Leave the current vehicle, if any. Lets a loaded save reposition the player
## cleanly instead of teleporting them while still parented to a car.
func eject() -> void:
	if _vehicle != null:
		_exit_vehicle()


func _toggle_vehicle() -> bool:
	if _vehicle != null:
		_exit_vehicle()
		return true
	var vehicle := _nearest_vehicle()
	if vehicle != null and not vehicle.has_driver():
		_enter_vehicle(vehicle)
		return true
	return false


## Use the nearest interactable in reach, if any. Reached only when the interact
## key didn't enter or exit a vehicle, so cars keep priority on the shared key.
func _try_interact() -> void:
	var target := _nearest_interactable()
	if target != null:
		target.interact(self)


## Nearest "interactables" node in reach implementing the contract
## (interact()/interact_prompt()), or null. Mirrors _nearest_vehicle; the
## selection math is the pure Interaction.nearest so it unit-tests headless.
func _nearest_interactable() -> Node3D:
	var bodies: Array[Node3D] = []
	var points := PackedVector3Array()
	for node in get_tree().get_nodes_in_group("interactables"):
		var body := node as Node3D
		if body == null or not body.has_method("interact"):
			continue
		bodies.append(body)
		points.append(body.global_position)
	var index := Interaction.nearest(points, global_position, interact_reach)
	return bodies[index] if index != Interaction.NONE else null


## Refresh the bottom-screen interact hint to the nearest interactable in reach.
## Nothing shows while driving or on the phone, where the key is already busy.
func _update_interact_prompt() -> void:
	if _interact_prompt == null:
		return
	if _vehicle != null or _on_phone():
		_interact_prompt.set_prompt("")
		return
	var target := _nearest_interactable()
	var text := ""
	if target != null and target.has_method("interact_prompt"):
		text = String(target.interact_prompt())
	_interact_prompt.set_prompt(text)


func _enter_vehicle(vehicle: Node3D) -> void:
	_vehicle = vehicle
	velocity = Vector3.ZERO
	visible = false
	collision_layer = 0
	collision_mask = 0
	vehicle.enter(self)


func _exit_vehicle() -> void:
	global_position = _vehicle.exit()
	_vehicle = null
	velocity = Vector3.ZERO
	visible = true
	collision_layer = 2
	collision_mask = 1
	_camera_rig.make_current()


## Vehicles are any Node3D in group "vehicles" implementing the
## enter(driver)/exit()/has_driver() contract (Car, Bike, Boat, ...).
func _nearest_vehicle() -> Node3D:
	var best: Node3D = null
	var best_distance := enter_vehicle_range
	for vehicle in get_tree().get_nodes_in_group("vehicles"):
		var body := vehicle as Node3D
		if body == null or not body.has_method("enter"):
			continue
		var distance := global_position.distance_to(body.global_position)
		if distance <= best_distance:
			best = body
			best_distance = distance
	return best


func _update_jump_timers(delta: float) -> void:
	if is_on_floor():
		_time_since_grounded = 0.0
		_jump_spent = false
	else:
		_time_since_grounded += delta
	if Input.is_action_just_pressed("jump"):
		_time_since_jump_pressed = 0.0
	else:
		_time_since_jump_pressed += delta


func _toggle_mouse_capture() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
