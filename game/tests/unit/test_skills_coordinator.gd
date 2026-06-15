class_name TestSkillsCoordinator
extends GdUnitTestSuite
## Tree-aware tests for the live PlayerSkills coordinator.

const SKILLS_COORDINATOR_SCRIPT := preload("res://scripts/systems/skills_coordinator.gd")


class PlayerStub:
	extends Node3D

	func _ready() -> void:
		add_to_group("player")


class VehicleStub:
	extends Node3D
	var driven: bool = true

	func _ready() -> void:
		add_to_group("vehicles")

	func has_driver() -> bool:
		return driven


class WeaponStub:
	extends Node
	signal hit_confirmed(killed: bool)

	func _ready() -> void:
		add_to_group("weapon_controller")


func test_on_foot_distance_trains_stamina() -> void:
	var player: PlayerStub = auto_free(PlayerStub.new())
	add_child(player)
	var coordinator: Node = auto_free(SKILLS_COORDINATOR_SCRIPT.new())
	player.add_child(coordinator)

	player.global_position = Vector3(25.0, 0.0, 0.0)
	coordinator._process(0.0)

	assert_float(coordinator.level("stamina")).is_greater(0.0)
	assert_float(coordinator.level("driving")).is_equal(0.0)


func test_driven_vehicle_distance_trains_driving_not_stamina() -> void:
	var player: PlayerStub = auto_free(PlayerStub.new())
	player.visible = false
	add_child(player)
	var vehicle: VehicleStub = auto_free(VehicleStub.new())
	add_child(vehicle)
	var coordinator: Node = auto_free(SKILLS_COORDINATOR_SCRIPT.new())
	player.add_child(coordinator)

	coordinator._process(0.0)
	vehicle.global_position = Vector3(80.0, 0.0, 0.0)
	coordinator._process(0.0)

	assert_float(coordinator.level("driving")).is_greater(0.0)
	assert_float(coordinator.level("stamina")).is_equal(0.0)


func test_hit_confirmed_trains_shooting() -> void:
	var player: PlayerStub = auto_free(PlayerStub.new())
	add_child(player)
	var weapon: WeaponStub = auto_free(WeaponStub.new())
	add_child(weapon)
	var coordinator: Node = auto_free(SKILLS_COORDINATOR_SCRIPT.new())
	player.add_child(coordinator)
	coordinator.call("_bind_weapon_controller")

	weapon.hit_confirmed.emit(false)

	assert_float(coordinator.level("shooting")).is_greater(0.0)


func test_save_round_trip_preserves_skills() -> void:
	var coordinator: Node = auto_free(SKILLS_COORDINATOR_SCRIPT.new())
	coordinator.restore({"skills": {"driving": 40.0, "shooting": 25.0}})
	var snapshot: Dictionary = coordinator.serialize()
	var restored: Node = auto_free(SKILLS_COORDINATOR_SCRIPT.new())
	restored.restore(snapshot)

	assert_float(restored.level("driving")).is_equal(40.0)
	assert_float(restored.level("shooting")).is_equal(25.0)
