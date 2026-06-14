extends SceneTree
## Runtime probe for the live CrowdPanicDirector in miami.tscn. Boots the map,
## asserts the director wired itself to the player's WeaponController.crime_committed,
## then fires a synthetic crime near mock pedestrians and asserts only those within
## scare_radius are spooked into fleeing. Self-contained (no miami_wiring_probe touch).
##   godot --headless --path game --script res://tests/crowd_panic_probe.gd

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const WARMUP_FRAMES: int = 120

var _scene: Node = null
var _frames: int = 0


class MockPed:
	extends Node3D
	var scared: bool = false

	func _ready() -> void:
		add_to_group("pedestrians")

	func scare(_threat_pos: Vector3, _seconds: float) -> void:
		scared = true


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("crowd panic probe: scene failed to load")
		quit(1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false
	var err := _verify()
	if err.is_empty():
		print("crowd panic probe: OK")
		quit(0)
	else:
		push_error("crowd panic probe FAIL: " + err)
		quit(1)
	return true


func _verify() -> String:
	var director := _scene.find_child("CrowdPanicDirector", true, false) as CrowdPanicDirector
	if director == null:
		return "CrowdPanicDirector not present in miami.tscn"
	var weapon := get_first_node_in_group("weapon_controller")
	if weapon == null:
		return "no live weapon_controller (crowd would never react to gunfire)"
	if not weapon.crime_committed.is_connected(Callable(director, "_on_crime")):
		return "director not wired to weapon_controller.crime_committed"
	# A crime near `here` must scare the near ped but not one across town.
	var here := Vector3(120, 0, 120)
	var near_ped := MockPed.new()
	var far_ped := MockPed.new()
	root.add_child(near_ped)
	root.add_child(far_ped)
	near_ped.global_position = here + Vector3(4, 0, 0)
	far_ped.global_position = here + Vector3(400, 0, 0)
	director._on_crime(false, here)
	if not near_ped.scared:
		return "ped near the shooting did not panic"
	if far_ped.scared:
		return "ped across town panicked (scare radius not respected)"
	return ""
