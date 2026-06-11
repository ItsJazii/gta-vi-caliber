class_name Player
extends CharacterBody3D
## Third-person player controller: walk, sprint, jump.
##
## Movement math is delegated to PlayerMotion (pure, unit-tested). The camera
## is owned by the CameraRig child (OrbitCamera); we only read its yaw so
## input is camera-relative.

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var acceleration: float = 30.0
@export var deceleration: float = 45.0
@export_range(0.0, 1.0) var air_control: float = 0.35
@export var jump_velocity: float = 4.8
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.12
@export var climb_speed: float = 3.0
## How close (m) a vehicle must be for the interact key to enter it.
@export var enter_vehicle_range: float = 3.5

var _time_since_grounded: float = 0.0
var _time_since_jump_pressed: float = 1.0
var _jump_spent: bool = false
var _vehicle: Car = null

@onready var _camera_rig: OrbitCamera = $CameraRig


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_mouse_capture()
	elif event.is_action_pressed("interact"):
		_toggle_vehicle()


func _physics_process(delta: float) -> void:
	if _vehicle != null:
		global_position = _vehicle.global_position
		return

	_update_jump_timers(delta)
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := PlayerMotion.direction_from_input(input_dir, _camera_rig.global_rotation.y)

	if _is_on_ladder() and (input_dir.y < 0.0 or not is_on_floor()):
		velocity = PlayerMotion.climb_velocity(input_dir, direction, climb_speed)
		move_and_slide()
		return

	if not is_on_floor():
		velocity += get_gravity() * delta
	if PlayerMotion.should_jump(
		_time_since_grounded, coyote_time, _time_since_jump_pressed, jump_buffer_time, _jump_spent
	):
		velocity.y = jump_velocity
		_jump_spent = true
		_time_since_jump_pressed = jump_buffer_time + 1.0

	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var target := PlayerMotion.horizontal_velocity(direction, speed)
	var rate := PlayerMotion.acceleration_rate(
		not input_dir.is_zero_approx(), is_on_floor(), acceleration, deceleration, air_control
	)
	velocity = PlayerMotion.accelerated(velocity, target, rate, delta)
	move_and_slide()


func _is_on_ladder() -> bool:
	for ladder in get_tree().get_nodes_in_group("ladders"):
		var area := ladder as Area3D
		if area != null and area.overlaps_body(self):
			return true
	return false


## Leaves the current vehicle if driving one (used by systems like save/load
## that need the player on foot before repositioning them).
func eject() -> void:
	if _vehicle != null:
		_exit_vehicle()


func _toggle_vehicle() -> void:
	if _vehicle != null:
		_exit_vehicle()
		return
	var car := _nearest_vehicle()
	if car != null and not car.has_driver():
		_enter_vehicle(car)


func _enter_vehicle(car: Car) -> void:
	_vehicle = car
	velocity = Vector3.ZERO
	visible = false
	collision_layer = 0
	collision_mask = 0
	car.enter(self)


func _exit_vehicle() -> void:
	global_position = _vehicle.exit()
	_vehicle = null
	velocity = Vector3.ZERO
	visible = true
	collision_layer = 2
	collision_mask = 1
	_camera_rig.make_current()


func _nearest_vehicle() -> Car:
	var best: Car = null
	var best_distance := enter_vehicle_range
	for vehicle in get_tree().get_nodes_in_group("vehicles"):
		var car := vehicle as Car
		if car == null:
			continue
		var distance := global_position.distance_to(car.global_position)
		if distance <= best_distance:
			best = car
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
