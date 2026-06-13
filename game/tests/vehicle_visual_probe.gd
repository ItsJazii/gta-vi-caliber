extends SceneTree

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const WARMUP_FRAMES: int = 180
const ROAD_SURFACE_Y: float = 0.32
const SURFACE_TOLERANCE: float = 0.08

var _scene: Node = null
var _frames: int = 0


func _initialize() -> void:
	var packed_scene: PackedScene = load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		_fail("Could not load %s" % SCENE_PATH)
		return

	_scene = packed_scene.instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false

	_run_checks()
	return true


func _run_checks() -> void:
	var playable_error: String = _check_playable_vehicles()
	if not playable_error.is_empty():
		_fail(playable_error)
		return

	var stats: Dictionary = _collect_visual_stats()
	var visual_error: String = stats.error
	if not visual_error.is_empty():
		_fail(visual_error)
		return

	var parked_layers: int = stats.parked_layers
	var parked_instances: int = stats.parked_instances
	var moving_traffic: int = stats.moving_traffic
	if parked_layers < 2 or parked_instances == 0:
		_fail("No parked imported vehicles were generated")
		return
	if moving_traffic == 0:
		_fail("No moving imported traffic vehicles were generated")
		return

	print(
		(
			"VEHICLE_VISUAL_PROBE PASS: parked=%d layers=%d moving=%d"
			% [parked_instances, parked_layers, moving_traffic]
		)
	)
	quit(0)


func _check_playable_vehicles() -> String:
	var player: Node3D = _scene.get_node_or_null("Player") as Node3D
	if player == null:
		return "Missing player"
	for car_name: String in [&"Car", &"Car2"]:
		var error := _check_playable_vehicle(car_name, player)
		if not error.is_empty():
			return error

	return ""


func _check_playable_vehicle(car_name: String, player: Node3D) -> String:
	var car: Node3D = _scene.get_node_or_null(car_name) as Node3D
	if car == null:
		return "Missing playable vehicle %s" % car_name
	if not car.is_in_group("starter_vehicles"):
		return "%s is not registered as a starter vehicle" % car_name
	if car.global_position.distance_to(player.global_position) > 25.0:
		return "%s was not moved near the player spawn" % car_name
	if car.get_node_or_null("Chassis") != null or car.get_node_or_null("Cabin") != null:
		return "%s still contains the legacy procedural body" % car_name
	return _check_vehicle_mesh(car_name, car)


func _check_vehicle_mesh(car_name: String, car: Node3D) -> String:
	var visual := VehicleVisualLibrary.first_mesh_instance(car)
	if visual == null:
		return "%s does not contain an imported vehicle mesh" % car_name
	var bottom_y := _mesh_bottom_y(visual)
	if absf(bottom_y - ROAD_SURFACE_Y) > SURFACE_TOLERANCE:
		return "%s tyre plane is %.2f, expected %.2f" % [car_name, bottom_y, ROAD_SURFACE_Y]
	return ""


func _collect_visual_stats() -> Dictionary:
	var parked_layers: int = 0
	var parked_instances: int = 0
	var moving_traffic: int = 0
	var stack: Array[Node] = [_scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if (
			node is MultiMeshInstance3D
			and (node.name == &"ParkedSportCoupes" or node.name == &"ParkedClassicSedans")
		):
			var multimesh_instance: MultiMeshInstance3D = node as MultiMeshInstance3D
			if multimesh_instance.multimesh == null or multimesh_instance.multimesh.mesh == null:
				return {"error": "%s has no traffic LOD mesh" % node.name}
			var mesh_bottom := multimesh_instance.multimesh.mesh.get_aabb().position.y
			if absf(VehicleVisualLibrary.MODEL_FLOOR_OFFSET_Y + mesh_bottom) > SURFACE_TOLERANCE:
				return {
					"error":
					(
						"%s LOD tyre plane is %.2f, expected local zero"
						% [
							node.name,
							VehicleVisualLibrary.MODEL_FLOOR_OFFSET_Y + mesh_bottom,
						]
					)
				}
			parked_layers += 1
			parked_instances += multimesh_instance.multimesh.instance_count
		elif node is TrafficCar:
			var visual: MeshInstance3D = node.get_node_or_null("VehicleVisual") as MeshInstance3D
			if visual == null or visual.mesh == null or visual.get_active_material(0) == null:
				return {"error": "Moving traffic car is missing its imported visual or material"}
			var traffic_bottom := _mesh_bottom_y(visual)
			if absf(traffic_bottom - ROAD_SURFACE_Y) > SURFACE_TOLERANCE:
				return {
					"error":
					(
						(
							"Moving traffic tyre plane is %.2f, expected %.2f "
							+ "(root=%.2f visual=%.2f mesh_min=%.2f)"
						)
						% [
							traffic_bottom,
							ROAD_SURFACE_Y,
							(node as Node3D).global_position.y,
							visual.position.y,
							visual.get_aabb().position.y,
						]
					)
				}
			moving_traffic += 1

		for child: Node in node.get_children():
			stack.push_back(child)

	return {
		"error": "",
		"parked_layers": parked_layers,
		"parked_instances": parked_instances,
		"moving_traffic": moving_traffic,
	}


func _mesh_bottom_y(visual: MeshInstance3D) -> float:
	var bounds := visual.get_aabb()
	var bottom_y := INF
	for x in [bounds.position.x, bounds.end.x]:
		for y in [bounds.position.y, bounds.end.y]:
			for z in [bounds.position.z, bounds.end.z]:
				bottom_y = minf(bottom_y, (visual.global_transform * Vector3(x, y, z)).y)
	return bottom_y


func _fail(message: String) -> void:
	push_error("VEHICLE_VISUAL_PROBE FAIL: %s" % message)
	quit(1)
