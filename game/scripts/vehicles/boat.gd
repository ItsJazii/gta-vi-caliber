class_name Boat
extends RigidBody3D
## Greybox boat: four-point buoyancy (corner float points give natural
## pitch/roll righting), propeller thrust and rudder torque while submerged.
## Math is delegated to BoatMotion (pure, unit-tested). Implements the same
## enter()/exit()/has_driver() contract Player expects from vehicles.

const FLOAT_POINTS: Array[Vector3] = [
	Vector3(-0.8, 0.0, -1.4),
	Vector3(0.8, 0.0, -1.4),
	Vector3(-0.8, 0.0, 1.4),
	Vector3(0.8, 0.0, 1.4),
]

## World-space height of the water surface this boat floats on.
@export var water_level: float = 0.5
## Buoyancy spring per float point, in g-per-meter-of-submersion terms. The level
## waterline sits at g/buoyancy_strength; 45 floats the hull ~0.22 m deep (≈27% of
## the 0.8 m hull) so it planes rather than wallowing half-submerged.
@export var buoyancy_strength: float = 45.0
@export var max_thrust: float = 13000.0
## Yaw authority of the rudder. Kept well below thrust so the boat carves a
## deliberate, steerable arc (~66°/s) instead of spinning on the spot.
@export var rudder_torque_max: float = 2400.0

var _driver: Node3D = null
var _ocean: Ocean = null

@onready var _camera: Camera3D = $CameraPivot/SpringArm/Camera
@onready var _exit_point: Marker3D = $ExitPoint


func has_driver() -> bool:
	return _driver != null


func enter(driver: Node3D) -> void:
	_driver = driver
	_camera.current = true


## Releases the driver and returns a safe world position to step out at.
func exit() -> Vector3:
	_driver = null
	_camera.current = false
	return _exit_point.global_position


func _physics_process(_delta: float) -> void:
	var submerged := false
	var point_strength := buoyancy_strength * mass / FLOAT_POINTS.size()
	for point in FLOAT_POINTS:
		var world_point := global_transform * point
		var depth := _water_height(world_point.x, world_point.z) - world_point.y
		if depth > 0.0:
			submerged = true
		var force := BoatMotion.buoyancy_force(depth, point_strength)
		apply_force(Vector3.UP * force, world_point - global_position)

	if _driver == null:
		return
	var throttle := VehicleMotion.driving_axis(
		Input.get_action_strength("move_back"), Input.get_action_strength("move_forward")
	)
	var steer := VehicleMotion.driving_axis(
		Input.get_action_strength("move_left"), Input.get_action_strength("move_right")
	)
	var forward := -global_transform.basis.z
	apply_central_force(forward * BoatMotion.thrust(throttle, max_thrust, submerged))
	apply_torque(
		(
			Vector3.UP
			* BoatMotion.rudder_torque(
				VehicleMotion.godot_steering(steer), rudder_torque_max, submerged
			)
		)
	)


## Water height at a world x/z: the live Gerstner ocean if one is in the scene
## (group "water"), else the flat `water_level` fallback so the boat still floats
## in scenes with no Ocean node — and so the pure BoatMotion math is unaffected.
## Sampling per float-point is what makes the hull pitch and roll with the swell
## instead of sitting on an invisible flat plane.
func _water_height(world_x: float, world_z: float) -> float:
	if _ocean == null or not is_instance_valid(_ocean):
		var nodes := get_tree().get_nodes_in_group("water")
		_ocean = nodes[0] as Ocean if not nodes.is_empty() else null
	if _ocean != null:
		return _ocean.surface_height(world_x, world_z)
	return water_level
